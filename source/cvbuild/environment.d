module cvbuild.environment;

import cvbuild.buildsettings;
import cvbuild.dubpackage;
import cvbuild.globals;
import cvbuild.helpers;

import std.conv : to;
import std.array : Appender;

string expandDubBuildVariables(string str, DubProject project, BuildSettings buildSettings, string[string] dubVariables)
{
	Appender!string expanded;

	size_t start, ind;
	for (ind=0; ind<str.length; ind++)
	{
		if (str[ind] != '$')
			continue;

		if (ind+1 < str.length && str[ind+1] == '$')
		{
			expanded ~= str[start..ind+1];
			ind++;
			start = ind+1;
			continue;
		}

		expanded ~= str[start..ind];
		start = ind;

		for (ind=ind+1; ind<str.length; ind++)
		{
			import std.ascii;
			if (!isAlpha(str[ind]) && str[ind] != '_')
				break;
		}
		string key = str[start..ind];
		start = ind;

		assert(key.length > 1);

		string* var = key in dubVariables;
		if (var)
			expanded ~= *var;
		else
		{
			// environment variable
			import std.process;
			string envVar = environment.get(key[1..$]);
			if (envVar)
				expanded ~= envVar;
			else
				expanded ~= key;
		}
	}
	if (start == 0 && ind == str.length)
		return str;
	else if (ind-start > 1)
		expanded ~= str[start..ind];

	if (printDebug)
		outputln("expanded dub string: ", expanded.data[]);
	return expanded.data[];
}

string[string] setupDubVariables(DubProject project, BuildSettings buildSettings)
{
	import std.path;
	string[string] dubVariables;
	//dubVariables["$$"] = "$";
	dubVariables["$DUB"] = "dub.exe";
	dubVariables["$ROOT_PACKAGE_DIR"] = dirName(project.dubPath);

	dubVariables["$ARCH"] = buildSettings.arch;
	dubVariables["$PLATFORM"] = buildSettings.platform;
	dubVariables["$PLATFORM_POSIX"] = buildSettings.platformPosix;
	dubVariables["$BUILD_TYPE"] = buildSettings.buildType;

	string rootPackageName = getRootPackageName(buildSettings.dubPackage);
	string subPackageName = null;
	if (rootPackageName == project.name || !rootPackageName)
		subPackageName = getSubPackageName(buildSettings.dubPackage);

	foreach (pkg; project.byPackages(subPackageName, buildSettings.configuration))
	{
		import std.format;
		import std.array : replace;
		import std.uni : toUpper;
		string varname = format("$%s_PACKAGE_DIR", pkg.fullname(pkg.subPackage).replace(":", "_").toUpper());
		dubVariables[varname] = dirName(project.dubPath);
	}

	return dubVariables;
}

void setupDubEnvironment(DubProject project, BuildSettings buildSettings)
{
	import std.process;

}

void setupDubVariablesForPackage(ref string[string] dubVariables, DubProject project)
{
	//dubVariables["$PACKAGE_DIR"] = dirName(project.dubPath);
}

void setupDubEnvironmentForPackage(DubProject project, BuildSettings buildSettings)
{

}

void testExpand() //unittest
{
	import std.process;
	import std.path;

	string rootPath = buildPath("projects", "foobar");
	DubProject project = new DubProject();
	project.name = "foobar";
	project.dubPath = buildPath(rootPath, "dub.json");

	BuildSettings buildSettings = new BuildSettings();
	buildSettings.arch = "x86_64";
	buildSettings.platform = "linux";

	string[string] dubVariables = setupDubVariables(project, buildSettings);
	setupDubVariablesForPackage(dubVariables, project);

	dubVariables["$DUB"] = "dub.exe";
	environment["ENV_VARIABLE_TO_BE_EXPANDED"] = "hello world";

	assert(expandDubBuildVariables("hello world", project, buildSettings, dubVariables) == "hello world");
	assert(expandDubBuildVariables("$DUB", project, buildSettings, dubVariables) == "dub.exe");
	assert(expandDubBuildVariables("hello $DUB world", project, buildSettings, dubVariables) == "hello dub.exe world");
	assert(expandDubBuildVariables("$DUB world", project, buildSettings, dubVariables) == "dub.exe world");
	assert(expandDubBuildVariables("hello $DUB", project, buildSettings, dubVariables) == "hello dub.exe");
	assert(expandDubBuildVariables("hello $$WORLD", project, buildSettings, dubVariables) == "hello $WORLD");
	assert(expandDubBuildVariables("$$", project, buildSettings, dubVariables) == "$");

	assert(expandDubBuildVariables("$ARCH", project, buildSettings, dubVariables) == "x86_64");
	assert(expandDubBuildVariables("$PLATFORM", project, buildSettings, dubVariables) == "linux");
	assert(expandDubBuildVariables("$FOOBAR_PACKAGE_DIR", project, buildSettings, dubVariables) == rootPath);

	assert(expandDubBuildVariables("$ENV_VARIABLE_TO_BE_EXPANDED", project, buildSettings, dubVariables) == "hello world");
	assert(expandDubBuildVariables("$ENV_VARIABLE_TO_BE_EXPANDED_NOT_FOUND", project, buildSettings, dubVariables) == "$ENV_VARIABLE_TO_BE_EXPANDED_NOT_FOUND");
}