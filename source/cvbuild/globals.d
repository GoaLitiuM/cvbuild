module cvbuild.globals;

import asdf;

import std.path;
import std.string;
import std.stdio;
import std.array : Appender;
import std.conv : to;

const bool parallelProcessing = true;

__gshared bool forceBuild = false;
__gshared bool cleanBuild = false;
__gshared bool runProject = false;
__gshared string[] runProjectArgs;
__gshared bool noBuild = false;
__gshared bool noModuleDepsResolve = false;
__gshared bool noCommands = false;
__gshared int numThreads = 0;
__gshared bool printTasks = true;
__gshared bool printTasksDone = true;
__gshared bool printCommands = false;
__gshared bool printTiming = false;
__gshared bool printTimestamps = false;
__gshared bool printTrivialWarnings = false;
__gshared bool printDebug = false;
__gshared bool printDirty = true;
__gshared bool printDependencyResolve = false;
__gshared bool printConfiguration = false;
//__gshared bool useSeparateStdout = true;


enum defaultArch = "x86_64";
version (Windows)
{
	enum defaultPlatform = "windows";
	const string binaryExt = ".exe";
	const string staticLibraryExt = ".lib";
	const string dynamicLibraryExt = ".dll";
	const string objectExt = ".obj";
}
else version (linux)
{
	enum defaultPlatform = "linux";
	const string binaryExt = "";
	const string staticLibraryExt = ".a";
	const string dynamicLibraryExt = ".so";
	const string objectExt = ".o";
}
else
	static assert(0, "unsupported platform");

class ModuleFile
{
	@serializationIgnore string name; // should match the module name
	string path;
	@serializationIgnore string fullpath;

	@serializationIgnore bool dirty = true;

	this(string name, string path, string workDir)
	{
		this.name = name;
		this.path = path;

		if (workDir)
			this.fullpath = absolutePath(path, workDir);
		else
			this.fullpath = path;
	}

	override size_t toHash() { return typeid(string).getHash(&path); }

    override bool opEquals(Object o)
    {
		ModuleFile m = cast(ModuleFile)o;
        return m && path == m.path;
    }
}

bool shouldExclude(string file, string[] excludedFiles)
{
	foreach (excluded; excludedFiles)
	{
		if (globMatch(file, excluded))
			return true;
	}
	return false;
}


version (Windows)
{
	@nogc @safe pure nothrow extern (Windows) bool IsDebuggerPresent();
    @nogc @safe pure nothrow extern (Windows) void OutputDebugStringA(in char*);
    @nogc @safe pure nothrow extern (Windows) void OutputDebugStringW(in wchar*);
}

void outputln(T...)(T args) //@safe
{
	version (Windows)
	{
		if (IsDebuggerPresent())
		{
			Appender!string buffer;
			foreach (arg; args)
        	{
				alias type = typeof(arg);

				static if(is(type == string))
					buffer ~= arg;
				else
					buffer ~= to!string(arg);
			}
			buffer ~= "\n\0"; // must be zero terminated

			OutputDebugStringA(&buffer.data[0]);
		}
		else
			writeln(args);
	}
	else
		writeln(args);
}

void warningln(T...)(T args)
{
	outputln("warning: ", args);
}

void errorln(T...)(T args)
{
	if (args.length > 0)
		outputln("error: ", args);
	stdout.flush(); // just in case

	version (Windows)
	{
		debug assert(!IsDebuggerPresent());
	}
	else
	{
		debug assert(0);
	}

	import core.stdc.stdlib;
	exit(1);
	assert(0);
}