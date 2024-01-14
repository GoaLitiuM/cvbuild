module cvbuild.tasks;

import cvbuild.buildsettings;
import cvbuild.globals;
import cvbuild.helpers;

import core.cpuid : threadsPerCPU;
import std.process;
import std.stdio;
import std.path;
import std.conv : to;
import std.algorithm.mutation : remove;
import std.format;
import core.thread : Thread;
import core.time : MonoTime, dur;
import std.array;
import core.sync.mutex : Mutex;

enum enableColorization = false;

bool runTasks(Command[] commands, string buildDir)
{
	MonoTime taskStartTime = MonoTime.currTime;

    int maxTasks = numThreads > 0 ? numThreads : threadsPerCPU;
    shared(bool) taskFailed = false;
	int maxTasksReached = 0;
	bool tryDemangle = false;


	Mutex commandLock = new Mutex();
	Mutex printLock = new Mutex();

	bool shouldRun()
	{
		if (taskFailed)
			return false;

		commandLock.lock();
		scope(exit) commandLock.unlock();
		return commands.length > 0;
	}

	Command getNextCommand()
	{
		Command task = null;
		commandLock.lock();
		for (int i=0; i<commands.length; i++)
		{
			bool skip = false;
			foreach (subtask; commands[i].required)
			{
				if (subtask.done)
				{
					//outputln("subtask ", subtask.name, " is done");
					continue;
				}

				//outputln("task ", commands[i].name, " depends on task ", subtask.name);

				skip = true;
				break;
			}

			if (!skip)
			{
				task = commands[i];
				commands = commands.remove(i);
				break;
			}
		}
		commandLock.unlock();
		return task;
	}

	auto threadDelegate = ()
	{
		char[2048] buffer;

		while (shouldRun())
		{
			Command cmd = getNextCommand();
			if (!cmd)
			{
				Thread.sleep(dur!("msecs")(10));
				continue;
			}

			printLock.lock();
			if (printTasks)
			{
				string timestampStr;

				if (printTimestamps)
					timestampStr = format!("%.3f: ")((MonoTime.currTime-taskStartTime).total!"hnsecs"*0.0000001);

				/*if (cmd.workDir)
					outputln(timestampStr, "> ", cmd.name, " (workDir: '", cmd.workDir, "')");
				else*/
					outputln(timestampStr, "> ", cmd.name);
			}
			if (printCommands)
				outputln(">>> ", cmd.getArgs().join(" "));
			printLock.unlock();

			MonoTime startTime = MonoTime.currTime;
			bool hadOutput = false;
			Appender!string linedata;
       		ProcessPipes process = pipeProcess(cmd.getArgs(), Redirect.stdout | Redirect.stderrToStdout, null, Config.suppressConsole, cmd.workDir);
			//t.process = pipeProcess(taskArgs, Redirect.stderr | Redirect.stdoutToStderr, null, Config.suppressConsole);
			Pid pid = process.pid;
			int taskRet;

			while (true)
			{
				char[] data = process.stdout.rawRead(buffer);
				if (data.length > 0)
					linedata ~= data.dup;

				auto waited = tryWait(pid);
				if (waited.terminated)
				{
					taskRet = waited.status;
					break;
				}
			}

			version (Windows)
				string[] lines = split(linedata.data, "\r\n");
			else
				string[] lines = split(linedata.data, "\n");

			printLock.lock();
			if (printTasks && printTasksDone && maxTasks > 1)
				outputln("< ", cmd.name);
			foreach (line; lines)
			{
				hadOutput = true;
				colorizeOutput(stdout, line);
			}

			if (taskRet != 0)
			{
				taskFailed = true;
				if (!hadOutput)
					outputln("Task exited with code: ", taskRet);
			}
			else
				cmd.done = true;
			printLock.unlock();
		}
	};

	if (maxTasks > 1)
	{
		Thread[] threads;
		for (int i=0; i<maxTasks; i++)
		{
			Thread thread = new Thread(threadDelegate);
			threads ~= thread;
			thread.start();
		}

		foreach (thread; threads)
			thread.join();
	}
	else
		threadDelegate();

	return !taskFailed;
}

static if (enableColorization)
{
void colorizeOutput(ref File file, string line)
{
    version (Windows)
    {
		// color information is lost when stdout/stderr is piped to another process,
        // so attempt to restore some of the color information

		// TODO: support msvc linker output as well?
		// source\input\inputhandler.d(79,28):        instantiated from here: `__ctor!(KeyInput)`

		import core.sys.windows.wincon;
		import core.sys.windows.winbase;
		import core.sys.windows.basetsd;
		import core.sys.windows.windef;

		import std.regex : regex, matchAll;
		import std.string : indexOf;
		enum regex_vcolumns = regex("^(.*)(\\(\\d+,\\d+\\)):\\s+(?:(Warning|Error|Deprecation):|\\s+)\\s+(.*)$", "gm");
		enum regex_fallback = regex("^(.*)(\\(\\d+\\)):\\s+(Warning|Error):\\s+(.*)$", "gm");

		enum FOREGROUND_WHITE = FOREGROUND_RED | FOREGROUND_BLUE | FOREGROUND_GREEN;

        CONSOLE_SCREEN_BUFFER_INFO info;
        HANDLE stdHandle = GetStdHandle(STD_OUTPUT_HANDLE); // shares the same handle with STD_ERROR_HANDLE
        if (!GetConsoleScreenBufferInfo(stdHandle, &info))
        {
            // no console?
            //file.write(line);
			outputln(line);
            return;
        }
        ushort attribs = info.wAttributes;

        void colorize(WORD color)
        {
            file.flush();
            SetConsoleTextAttribute(stdHandle, color);
        }
        void resetColor()
        {
            file.flush();
            SetConsoleTextAttribute(stdHandle, attribs);
        }
        void rewind()
        {
            file.flush();
            COORD pos = info.dwCursorPosition;
            pos.X = 0;
            pos.Y -= 1;

            SetConsoleCursorPosition(stdHandle, pos);
            // clear current line
            file.write("\33[2K");
        }

		auto r = regex_vcolumns;
        auto matches = matchAll(line, r);
        if (!matches)
        {
            r = regex_fallback; // without -vcolumn
            matches = matchAll(line, r);
        }
        if (matches)
        {
            foreach (m; matches)
            {
                colorize(FOREGROUND_WHITE | FOREGROUND_INTENSITY);
                file.write(m[1]);
                file.write(m[2], ": ");
                if (m[3] == "Error")
                    colorize(FOREGROUND_RED | FOREGROUND_INTENSITY);
                else
                    colorize(FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_INTENSITY);
                file.write(m[3], ": ");
                resetColor();

                bool intensity = false;
                foreach (c; m[4])
                {
                    if (c == '`')
                    {
                        intensity = !intensity;
                        if (intensity)
                            colorize(FOREGROUND_WHITE | FOREGROUND_INTENSITY);
                        else
                            resetColor();
                        continue;
                    }

                    file.write(c);
                }

                resetColor();
            }
        }
        else if (line.indexOf("Compiling ") == 0)
        {
            file.write(line[0.."Compiling ".length]);
            colorize(FOREGROUND_INTENSITY);
            file.write(line["Compiling ".length..line.length]);
            resetColor();
        }
        else
            file.write(line);
    }
    else
        file.write(line);

	file.writeln();
}
}
else
{
void colorizeOutput(ref File file, string line)
{
	import core.sys.windows.wincon;
	import core.sys.windows.winbase;
	import core.sys.windows.basetsd;

	CONSOLE_SCREEN_BUFFER_INFO info;
	HANDLE stdHandle = GetStdHandle(STD_OUTPUT_HANDLE); // shares the same handle with STD_ERROR_HANDLE
	if (!GetConsoleScreenBufferInfo(stdHandle, &info))
	{
		// no console?
		//file.write(line);
		outputln(line);
		return;
	}

	file.write(line);
	file.writeln();
}
}