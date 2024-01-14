/+ dub.sdl:
name: cvbuildTestRunner
+/
import std.stdio;
import std.file;
import std.string;
import std.algorithm.sorting;
import std.algorithm : min;
import std.ascii;
import std.path;
import std.conv : to, parse;
import std.array;
import std.process;
import std.parallelism;

__gshared bool parallelTests = true;
__gshared bool skipTests = false;
__gshared bool skipProjectTests = false;
__gshared bool skipBugTests = false;
__gshared bool skipRun = false;
__gshared bool printOutputAlways = true;
__gshared bool skipChecks = false;

alias alphaNumSort = (a, b)
{
	// quick and dirty version of alphanumerical sorting,
	// assumes the first numbers start at exact same position
	// - 0-btest, 1-atest
	// - test-0-b, test-1-a
	size_t len = min(a.length, b.length);
	size_t i = 0;
	for (; i<len; i++)
	{
		if (a[i] == b[i])
			continue;
		else if (isDigit(a[i]) && isDigit(b[i]))
		{
			string aa = a[i..$];
			string bb = b[i..$];
			int anum = parse!(int)(aa);
			int bnum = parse!(int)(bb);
			return anum < bnum;
		}
		break;
	}

	return a[i..$] < b[i..$]; // characters up to i are equal
	//return a < b;
};

string getAllLines(File file)
{
	string[] lines;
	foreach (line; file.byLine)
		lines ~= strip(line).idup;

	return lines.join("\n");
}

void cleanPath(string targetPath)
{
	const string[] defaultCleanFiles =
	[
		"build", ".dub", "dub.selections.json",
		"test.exe", "test.lib", "test.dll", "test.ilk", "test.pdb",
		"test", "test.a"
	];

	string[] cleanFiles;
	foreach (str; defaultCleanFiles)
		cleanFiles ~= buildPath(targetPath, str);

	if (exists(buildPath(targetPath, "clean")))
	{
		foreach (line; File(buildPath(targetPath, "clean"), "r").byLine)
			cleanFiles ~= buildPath(targetPath, buildNormalizedPath(to!string(line)));
	}

	foreach (DirEntry dir; dirEntries(targetPath, SpanMode.shallow))
	{
		if (exists(buildPath(dir.name, "clean")))
		{
			cleanPath(dir.name);
			/*foreach (str; defaultCleanFiles)
				cleanFiles ~= buildPath(dir.name, str);

			foreach (line; File(buildPath(dir.name, "clean"), "r").byLine)
				cleanFiles ~= buildPath(dir.name, buildNormalizedPath(to!string(line)));*/
		}
	}

	foreach (filePath; cleanFiles)
	{
		if (isAbsolute(filePath) || filePath.startsWith("..")  || filePath == ".")
		{
			writeln("invalid path '", filePath, "', the path must be relative");
			continue;
		}

		if (!exists(filePath))
			continue;

		if (isDir(filePath))
			rmdirRecurse(filePath);
		else
			remove(filePath);
	}
}

struct FailedTest
{
	string testPath;
	string message;
	string output;
	string expectedOutput;
}

bool runTests(string[] buildArgs, string specificTest = null, )
{
    string[] tests;
	string[] projectTests;
	string[] allTests;
	int skippedTests = 0;

	if (specificTest)
	{
		if (exists(specificTest))
			tests ~= specificTest;
		else
		{
			writeln("test '", specificTest, "' not found");
			return false;
		}
	}
	else
	{
		foreach(DirEntry dir; dirEntries(".", SpanMode.shallow))
		{
			if (dir.isDir())
			{
				if (exists(buildPath(dir.name, "skip")))
				{
					skippedTests++;
					continue;
				}

				string name = baseName(dir.name);
				bool isTest = name.length > 1 && isDigit(name[0]);
				bool isProjectTest = name.length > 1 && name[0] == 'p' && isDigit(name[1]);
				bool isBugTest = name.length > 1 && name[0] == 'b' && isDigit(name[1]);

				if (isTest && !skipTests)
				{
					tests ~= buildNormalizedPath(dir.name);
					continue;
				}
				else if (isProjectTest && !skipProjectTests)
				{
					projectTests ~= buildNormalizedPath(dir.name);
					continue;
				}
				else if (isBugTest && !skipBugTests)
				{
					tests ~= buildNormalizedPath(dir.name);
					continue;
				}

				skippedTests++;
			}
		}
		tests = tests.sort!alphaNumSort().release;
		projectTests = projectTests.sort!alphaNumSort().release;
	}
	allTests = tests ~ projectTests;

	foreach (testPath; parallel(allTests))
		cleanPath(testPath);

	FailedTest[] failedTests;

	void failTest(string testPath, string message, string output, string expectedOutput = null)
	{
		synchronized
		{
			failedTests ~= FailedTest(testPath, message, output, expectedOutput);
		}
	}

	int waitOutput(ProcessPipes pipes, ref string output)
	{
		output = null;
		string errors = null;
		int ret;
		while (true)
		{
			// other process could get stuck on full stdout so we must flush it periodically
			//if (pipes.stdout.size() > 0)
				output ~= getAllLines(pipes.stdout);
			//if (pipes.stderr.size() > 0)
			//	errors ~= getAllLines(pipes.stderr);
			auto w = tryWait(pipes.pid);
			if (w.terminated)
			{
				ret = w.status;
				break;
			}
			import core.thread;

			//Thread.sleep(dur!"hnsecs"(1));
		}

		output ~= getAllLines(pipes.stdout);
		//errors ~= getAllLines(pipes.stderr);

		// redirected stderr seems to always get written out of order
		if (errors.length > 0)
			output ~= "\n" ~ errors;

		return ret;
	}

	void doTest(string testPath)
	{
		// pre-clean in case the last run failed for some reason
		cleanPath(testPath);

		/*if (exists(buildPath(testPath, "skip")))
		{
			synchronized
			{
				skippedTests++;
			}
			return;
		}*/

		string expectedOutput;
		if (exists(buildPath(testPath, "output")))
			expectedOutput = getAllLines(File(buildPath(testPath, "output"), "r"));
		else
			expectedOutput = "ok";

		string[] extraArgs;
		if (exists(buildPath(testPath, "args")))
			extraArgs ~= getAllLines(File(buildPath(testPath, "args"), "r")).split("\n");

		string[] mustExist;
		if (exists(buildPath(testPath, "exists")))
			mustExist ~= getAllLines(File(buildPath(testPath, "exists"), "r")).split("\n");

		bool buildfail = exists(buildPath(testPath, "buildfail"));
		bool norun = skipRun || exists(buildPath(testPath, "norun"));

		//ProcessPipes buildProcess = pipeProcess(buildArgs, Redirect.stdin | Redirect.stdout | Redirect.stderr/*| Redirect.stderrToStdout*/, null, Config.none, testPath);
		ProcessPipes buildProcess = pipeProcess(buildArgs ~ extraArgs, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout, null, Config.none, testPath);
		//Pid pid = spawnProcess(buildArgs, stdin, stderr, stdout, null, Config.suppressConsole, testPath);
		string buildOutput;
		if (waitOutput(buildProcess, buildOutput) != 0)
		//if (wait(pid) != 0)
		{
			if (!buildfail)
			{
				failTest(testPath, "build failure", buildOutput);
				return;
			}
			//writeln("build failed as expected: ", buildOutput);
		}
		else if (buildfail)
		{
			failTest(testPath, "build was expected to fail", null);
			return;
		}

		//if (printOutputAlways)
		//	writeln(buildOutput);

		//writeln("norun: ", norun, " buildfail: ", buildfail);

		string testOutput;
		if (norun || buildfail)
		{}
		else //if (!norun && !buildfail)
		{
			string targetName;
			ProcessPipes describeProcess = pipeProcess(["dub", "describe", "--data-list", "--data=target-name"], Redirect.all, null, Config.suppressConsole, testPath);
			wait(describeProcess.pid);

			targetName = getAllLines(describeProcess.stdout);
			if (!targetName)
			{
				//writeln(testPath,": could not determine targetName, assuming 'test'");
				targetName = "test";
				//failTest(testPath, "missing target-name", null);
				//return;
			}

			version (Windows)
				const string targetExtension = ".exe";
			else
				const string targetExtension = "";

			targetName = buildPath(testPath, targetName ~ targetExtension);

			if (!exists(targetName))
			{
				failTest(testPath, "targetName '" ~ targetName ~ "' doesn't exist", buildOutput);
				return;
			}

			ProcessPipes testProcess = pipeProcess(targetName, Redirect.all, null, Config.suppressConsole, testPath);
			int returnCode = wait(testProcess.pid);
			testOutput = getAllLines(testProcess.stdout);
			if (returnCode != 0)
			{
				failTest(testPath, "return code: " ~ to!string(returnCode), testOutput != expectedOutput ? testOutput : null);
				return;
			}
			if (testOutput != expectedOutput)
			{
				failTest(testPath, null, testOutput, expectedOutput);
				return;
			}
		}

		if (!skipChecks)
		foreach (file; mustExist)
		{
			if (!exists(buildPath(testPath, file)))
			{
				failTest(testPath, "file '" ~ file ~ "' does not exist", buildOutput, null);
				return;
			}
		}

		cleanPath(testPath);
	}

	import std.algorithm.mutation : reverse;
	if (!parallelTests) foreach (testPath; tests)
		doTest(testPath);
	else foreach (testPath; parallel(tests.reverse)) // running slower tasks first is a bit faster
		doTest(testPath);

	// run more intensive project tests one by one
	foreach (testPath; projectTests)
		doTest(testPath);
	/*if (!parallelTests) foreach (testPath; projectTests)
		doTest(testPath);
	else foreach (testPath; parallel(projectTests.reverse)) // running slower tasks first is a bit faster
		doTest(testPath);*/

	foreach (test; failedTests)
	{
		if (test.output)
		{
			if (test.expectedOutput && test.expectedOutput != "ok")
			{
				writeln(test.testPath, " failed, expected output:\n", test.expectedOutput, "\n");
				writeln("output:\n", test.output, "\n");
			}
			else if (test.message)
				writeln(test.testPath, " failed: ", test.message, ", output:\n", test.output, "\n");
			else
				writeln(test.testPath, " failed, output:\n", test.output, "\n");
		}
		else if (test.message)
			writeln(test.testPath, " failed: ", test.message);
		else
			writeln(test.testPath, " failed");
	}

	/*if (failedTests.length == 0)
	{
		foreach (testPath; parallel(allTests))
			cleanPath(testPath);
	}*/

	if (!specificTest)
	{
		write("succeeded tests: ", allTests.length-failedTests.length, "/", allTests.length);
		if (skippedTests > 0)
			write(", skipped ", skippedTests);
		if (failedTests.length > 0)
			write(", failed ", failedTests.length);
		writeln();

		if (failedTests.length > 0)
		{
			string[] failedTestNames;
			foreach (test; failedTests)
				failedTestNames ~= test.testPath;
			writeln("failed tests: ", failedTestNames.join(", "));
		}
	}

	return failedTests.length == 0;
}


//static if (standaloneTests)
//{
	int main(string[] args)
	{
		import core.time;
		MonoTime startTime = MonoTime.currTime;

		string singleTest;
		bool parseOnly = false;

		foreach (arg; args[1..$])
		{
			if (arg == "--parseonly")
				parseOnly = true;
			else if (arg == "--norun")
				skipRun = true; // build only, assume output is ok
			else if (arg == "--benchmark")
			{
				parseOnly = true;
				skipRun = true;
			}
			else if (arg.startsWith("-"))
			{}
			else
				singleTest = arg;
		}

		//singleTest = args.length > 1 ? args[1] : null;
		if (singleTest)
			parallelTests = false;
		scope(exit)
		{
			if (!singleTest)
				writeln("test time: ", cast(long)((MonoTime.currTime-startTime).total!"hnsecs"*0.0001), "ms");
		}

		string[] cvbuildArgs = ["../cvbuild", "build", "--rebuild", "--verbose"];
		/*if (jobsParallel)
			cvbuildArgs ~= "--jobs=0";
		else
			cvbuildArgs ~= "--jobs=1";*/


		if (skipRun)
			writeln("warning: running test executable is disabled, assuming all output is valid");

		if (parseOnly)
		{
			writeln("warning: building tests is disabled, parse only");
			cvbuildArgs ~= "--nobuild";
			cvbuildArgs ~= "--jobs=1";
			skipChecks = true;
		}
		else
			cvbuildArgs ~= "--jobs=0";

		/*if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with dub...");
			if (!runTests(["dub", "build", "--force", "--quiet", "--compiler=dmd"], singleTest))
				return 1;
		}*/


		//if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with cvbuild (dmd, project)...");
			if (!runTests(cvbuildArgs ~ ["--buildMode=project", "--compiler=dmd"], singleTest))
				return 1;
		}
		if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with cvbuild (ldc2, project)...");
			if (!runTests(cvbuildArgs ~ ["--buildMode=project", "--compiler=ldc2"], singleTest))
				return 1;
		}


		if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with cvbuild (dmd, package)...");
			if (!runTests(cvbuildArgs ~ ["--buildMode=package", "--compiler=dmd"], singleTest))
				return 1;
		}
		if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with cvbuild (ldc2, package)...");
			if (!runTests(cvbuildArgs ~ ["--buildMode=package", "--compiler=ldc2"], singleTest))
				return 1;
		}

		bool parallelTests_old = parallelTests;
		parallelTests = false; // this is too memory intensive
		if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with cvbuild (dmd, module)...");
			if (!runTests(cvbuildArgs ~ ["--buildMode=module", "--compiler=dmd", "--jobs=0"], singleTest))
				return 1;
		}
		if (false)
		{
			MonoTime startTimeTest = MonoTime.currTime;
			scope(exit)
				writeln("time: ", cast(long)((MonoTime.currTime-startTimeTest).total!"hnsecs"*0.0001), "ms");

			writeln("running tests with cvbuild (ldc2, module)...");
			if (!runTests(cvbuildArgs ~ ["--buildMode=module", "--compiler=ldc2", "--jobs=1"], singleTest))
				return 1;
		}
		parallelTests = parallelTests_old;
		return 0;
	}
//}