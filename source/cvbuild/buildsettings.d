module cvbuild.buildsettings;

import asdf;
import cvbuild.globals;
import cvbuild.helpers;

enum BuildMode
{
	Auto,		// deps inherits the value from root project
	Project,	// dub default
	Package,
	Module,		// single-file
}

class Command
{
    string name;
    string moduleName;
	string packageName;
    string[] args;

	string[] linkInputsSystem;
	string[] linkInputs;
	ModuleFile[] moduleInputs;
    string[] outputs;
    Command[] required;
    Command[] depends;

	string workDir = null;
    bool done = false;

	string[] getArgs()
	{
		string[] fullArgs;
		fullArgs ~= args[0];
		fullArgs ~= getInputFiles();
		fullArgs ~= args[1..$];
		return fullArgs;
	}

	string[] getInputFiles()
	{
		string[] files;
		foreach (mod; moduleInputs)
			files ~= mod.path;

		files ~= linkInputsSystem;
		files ~= linkInputs;

		return files;
	}
}

import std.datetime;
struct SysTimeProxy
{
	SysTime systime;
	alias systime this;

	static SysTimeProxy deserialize(Asdf data)
	{
		long val;
		deserializeValue!long(data, val);
		SysTime t = SysTime(val);
		return SysTimeProxy(t);
	}

	void serialize(S)(ref S serializer)
	{
		serializer.putValue(systime.stdTime());
	}
}

class BuildSettings
{
	static BuildSettings load(string file)
	{
		import std.file;
		return readText(file).deserialize!BuildSettings;
	}

	string dubPackage = null;
	string platform = defaultPlatform;
    string buildType = "debug";
    string arch = defaultArch;
    string compiler = "dmd";
	string configuration = null;
	bool unitTest = false;
	BuildMode buildMode = BuildMode.Package;
	BuildMode buildModeDeps = BuildMode.Auto;
	string outputName = null; // overrides the targetName of the output produced by the build

	@serializedAs!SysTimeProxy SysTime lastBuildTime;
	@serializedAs!SysTimeProxy SysTime compilerModifiedTime;

	@serializationIgnore string buildTarget = null;
	@serializationIgnore string mainDir = null;

	@serializationIgnore string[string] dubVariables;

	string platformPosix()
	{
		if (platform == "linux")
			return "posix";
		else
			return platform;
	}

    string compilerPath()
	{
		return compiler;
	};

	private @serializationIgnore string[] platformCombinationsCache;
	string[] getPlatformCombinations()
	{
		//if (platformCombinationsCache)
		//	return platformCombinationsCache;

		string compilerKind = compiler;
		switch (compiler)
		{
			case "ldc2":
				compilerKind = "ldc";
				break;
			case "ldmd2":
				compilerKind = "dmd";
				break;
			default:
				break;
		}

		platformCombinationsCache = [""] ~ getCombinations2(["", platform] ~ buildPlatformsExtra, ["", arch], ["", compilerKind]);
		return platformCombinationsCache;
	}

	bool platformMatches(string str)
	{
		if (str == null)
			return true;

		string[] combinations = getPlatformCombinations();
		foreach (c; combinations)
		{
			if (str == c)
				return true;
		}
		return false;
	}

    /*override bool opEquals(Object otherObject) const
    {
        if (otherObject == this)
            return true;

        if (BuildSettings other = cast(BuildSettings)otherObject)
        {
            return isSame(other);
        }

        return false;
    }*/

    bool changed(BuildSettings other)
    {
        if (dubPackage == other.dubPackage &&
			platform == other.platform &&
			buildType == other.buildType &&
			arch == other.arch &&
			compiler == other.compiler &&
			buildMode == other.buildMode &&
			buildModeDeps == other.buildModeDeps)
        {
            return false;
        }
        return true;
    }

	string getJson()
	{
		return serializeToJson(this);
	}
}

private enum buildPlatformsCompiler = [ "", "dmd", "ldc", "gdc" ];
private enum buildPlatformsArch = [ "", "x86", "x86_64" ];

version (Windows)
{
	private enum buildPlatforms = [ "", "windows" ];
	enum buildPlatformsExtra = [];
}
else version (Linux)
{
	private enum buildPlatforms = [ "", "linux", "posix" ];
	enum buildPlatformsExtra = [ "posix" ];
}
else version (OSX)
{
	private enum buildPlatforms = [ "", "osx", "posix" ];
	enum buildPlatformsExtra = [ "posix" ];
}
else version (Posix)
{
	private enum buildPlatforms = [ "", "posix" ];
	enum buildPlatformsExtra = [];
}
else
	static assert(0, "unsupported platform");

//private enum buildPlatformCombinations = getCombinations(buildPlatforms, buildPlatformsArch, buildPlatformsCompiler);