module cvbuild.main;

import cvbuild.dubpackage;
import cvbuild.globals;
import cvbuild.buildsettings;
import cvbuild.helpers;
import cvbuild.tasks;
import cvbuild.buildconfiguration;
import cvbuild.dub.dependencyresolver;
import cvbuild.serialization;
import cvbuild.environment;

import std.string;
import std.conv : to;
import std.array : Appender;
import std.datetime;
import core.time : MonoTime, Duration;

// runtests.bat --benchmark: (27/27, skipped 9)

// 185ms	null
// 202ms	load mainProject only
// 230ms	all
// 542ms	all + configure
// 588ms	all + configure + command(no module deps resolve)
// 1335ms	all + configure + commands

// breakdown
// 17ms 	main project
// 14ms 	deps projects
// 312ms	configure
// 46ms		commands
// 747ms	module deps resolve

// 0.523x ldc2 optimization factor without overhead

int main(string[] args)
{
/*
	testIter();
	import cvbuild.environment;
	testExpand();

	return 0;*/

	MonoTime startTime = MonoTime.currTime;
	int ret = run(args);
	outputln("\ncvbuild time: ", cast(long)((MonoTime.currTime-startTime).total!"hnsecs"*0.0001), "ms");
	return ret;
}

int run(string[] args)
{
	BuildSettings buildSettings = new BuildSettings();
	if (!parseOptions(args, buildSettings))
		return -2;

	MonoTime parseStartTime = MonoTime.currTime;
	DubProject project = loadMainPackage("dub.json", buildSettings);

	if (printTiming)
		outputln("cvbuild parse time: ", cast(long)((MonoTime.currTime-parseStartTime).total!"hnsecs"*0.0001), "ms");

	if (printDependencyResolve)
		printDependencyTree(project, buildSettings);

	//if (noBuild) // for timing benchmarks
	//	return 0;

	buildSettings.dubVariables = setupDubVariables(project, buildSettings);
	//setupDubVariablesForPackage(buildSettings.dubVariables, project);

	runPreGenerateCommands(project, buildSettings);

	MonoTime configStartTime = MonoTime.currTime;

	BuildConfiguration buildConfig = BuildConfiguration.create(project, buildSettings);

	if (printTiming)
		outputln("cvbuild configuration time: ", cast(long)((MonoTime.currTime-configStartTime).total!"hnsecs"*0.0001), "ms");

	runPostGenerateCommands(project, buildSettings);

	//if (noBuild) // for timing benchmarks
	//	return 0;

	runPreBuildCommands(project, buildSettings);

	if (/*!noBuild && */!build(project, buildConfig, buildSettings))
	{
		outputln("build failed");
		return -1;
	}

	runPostBuildCommands(project, buildSettings);

	if (runProject)
	{
		runPreRunCommands(project, buildSettings);

		// TODO: run project
		outputln("run: ", runProjectArgs);

		runPreRunCommands(project, buildSettings);
	}

	return 0;
}

void runPreGenerateCommands(DubProject project, BuildSettings buildSettings)
{
	runPackageCommands!"preGenerateCommands"(project, buildSettings);
}

void runPostGenerateCommands(DubProject project, BuildSettings buildSettings)
{
	runPackageCommands!"postGenerateCommands"(project, buildSettings);
}

void runPreBuildCommands(DubProject project, BuildSettings buildSettings)
{
	runPackageCommands!"preBuildCommands"(project, buildSettings);
}

void runPostBuildCommands(DubProject project, BuildSettings buildSettings)
{
	runPackageCommands!"postBuildCommands"(project, buildSettings);
}

void runPreRunCommands(DubProject project, BuildSettings buildSettings)
{
	runPackageCommands!"preRunCommands"(project, buildSettings);
}

void runPostRunCommands(DubProject project, BuildSettings buildSettings)
{
	runPackageCommands!"postRunCommands"(project, buildSettings);
}

void runPackageCommands(string settingName)(DubProject project, BuildSettings buildSettings)
{
	if (noCommands)
		return;

	string rootPackageName = getRootPackageName(buildSettings.dubPackage);
	string subPackageName = null;
	if (rootPackageName == project.name || !rootPackageName)
		subPackageName = getSubPackageName(buildSettings.dubPackage);

	bool terminate = false;
	foreach (pkg; project.byPackages(subPackageName, buildSettings.configuration))
	{
		string name = pkg.rootPackage ? (pkg.rootPackage ~ ":" ~ pkg.name) : (pkg.subPackage ? (pkg.name ~ ":" ~ pkg.subPackage) : pkg.name);
		string[] preGenerateCommands = getPlatformFlags!(settingName)(pkg, buildSettings, pkg.configuration, pkg.subPackage);
		if (preGenerateCommands.length == 0)
			continue;

		terminate = true;
		outputln("running ", settingName, " for ", name, "...");
		foreach (cmd; preGenerateCommands)
		{
			// FIXME
			outputln("cmd: ", cmd);
		}
	}
	if (terminate)
		terminate = terminate;//assert(0);
}

void printDependencyTree(DubProject project, BuildSettings buildSettings)
{
	string rootPackageName = getRootPackageName(buildSettings.dubPackage);
	string subPackageName = null;
	if (rootPackageName == project.name || !rootPackageName)
		subPackageName = getSubPackageName(buildSettings.dubPackage);

	{
		string fullName = project.rootPackage ? (project.rootPackage ~ ":" ~ project.name) : (subPackageName ? (project.name ~ ":" ~ subPackageName) : project.name);
		if (project.version_)
			outputln(fullName, ": ", project.version_);
		else
			outputln(fullName, ": *");
	}
	foreach (pkg; project.byDependencies(subPackageName, buildSettings.configuration))
	{
		string fullName = pkg.rootPackage ? (pkg.rootPackage ~ ":" ~ pkg.name) : (pkg.subPackage ? (pkg.name ~ ":" ~ pkg.subPackage) : pkg.name);
		string indent;
		for (int i=0; i<pkg.depth; i++)
			indent ~= "  ";

		import std.path;
		if (pkg.version_)
			outputln(indent, fullName, ": ", pkg.version_);
		else
			outputln(indent, fullName, ": ", dirName(pkg.dubPath));

	}
}

int parseOptions(string[] args, BuildSettings buildSettings)
{
    foreach (i, arg; args[1..$])
    {
        import std.uni;

        string option = arg;
        string value;
        if (arg.indexOf("=") != -1)
        {
            option = arg[0..arg.indexOf("=")];
            value = arg[arg.indexOf("=")+1..$];
        }
        option = toLower(option);

        if (option == "--help" || option == "-help" || option == "/?")
        {
			outputln("usage: cvbuild <buildDirectory> [options]");
			outputln("\noptions:");
            outputln("--clean\t\t\tcleans the build directory");
            outputln("--rebuild\t\t\tforce rebuild");
			outputln("--verbose\t\t\tverbose build output");
			outputln("--jobs=VALUE\t\t\tdefines how many build jobs can be run in parallel, defaults to all available cores");
			outputln("--buildMode=VALUE\t\t\tspecifies how build process is split, supported values:");
			outputln("\t\t\t\t\t project\t\tbuilds the whole project");
			outputln("\t\t\t\t\t package\t\tbuilds module packages separately");
			outputln("\t\t\t\t\t module\t\tbuilds each module separately");
			outputln("--buildModeDeps=VALUE\t\t\toverrides --buildMode for dependencies, defaults to same value as --buildMode");
			outputln("");
			outputln("--compiler=VALUE\tname or path to compiler");
			outputln("--arch=VALUE\tbuild architecture ('x86', 'x86_64' etc.)");
			outputln("--build=VALUE\tbuild type ('debug', 'release' etc.)");
			outputln("--config=VALUE\tbuild configuration");
            return 0;
        }
        else if (option == "--verbose")
        {
            printCommands = true;
            printTiming = true;
            printTrivialWarnings = true;
			printDirty = true;
			printDependencyResolve = true;
        }
        else if (option == "--timing")
            printTiming = true;
		else if (option == "--timestamps")
            printTimestamps = true;
        else if (option == "--clean")
            cleanBuild = true;
        else if (option == "--rebuild" || option == "--force" || option == "-f")
            forceBuild = true;
		else if (option == "--nobuild")
			noBuild = true;
        else if (option == "--compiler")
        {
            if (!value)
            {
                outputln("missing value, expected ", option, "=<compiler>");
                return false;
            }
			else if (value != "dmd" && value != "ldc2" && value != "gdc")
			{
                outputln("unsupported compiler: ", value);
                return false;
            }
            buildSettings.compiler = value;
        }
        else if (option == "--build" || option == "-b")
        {
            if (!value)
            {
                outputln("missing value, expected ", option, "=<buildType>");
                return false;
            }
            buildSettings.buildType = value;
        }
		else if (option == "--arch" || option == "-a")
        {
            if (!value)
            {
                outputln("missing value, expected ", option, "=<arch>");
                return false;
            }
            buildSettings.arch = value;
        }
		else if (option == "--buildmode")
        {
            if (!value)
            {
                outputln("missing value, expected ", option, "=<buildMode>");
                return false;
            }
			if (value == "project")
            	buildSettings.buildMode = BuildMode.Project;
			else if (value == "package")
            	buildSettings.buildMode = BuildMode.Package;
			else if (value == "module" || value == "singleFile")
            	buildSettings.buildMode = BuildMode.Module;
			else
			{
				outputln("unsupported value for --buildMode");
				return false;
			}
        }
		else if (option == "--buildmodedeps")
        {
            if (!value)
            {
                outputln("missing value, expected ", option, "=<buildMode|auto>");
                return false;
            }
			if (value == "project")
            	buildSettings.buildModeDeps = BuildMode.Project;
			else if (value == "package")
            	buildSettings.buildModeDeps = BuildMode.Package;
			else if (value == "module" || value == "singleFile")
            	buildSettings.buildModeDeps = BuildMode.Module;
			else if (value == "auto")
            	buildSettings.buildModeDeps = BuildMode.Auto;
			else
			{
				outputln("unsupported value for --buildModeDeps");
				return false;
			}
        }
		else if (option == "--build-mode")
        {
			outputln("DUB compatible option detected, please use --buildMode instead.");

            if (!value)
            {
                outputln("missing value, expected ", option, "=<buildMode>");
                return false;
            }
			if (value == "separate")
            	buildSettings.buildMode = BuildMode.Project;
			else if (value == "singleFile")
            	buildSettings.buildMode = BuildMode.Module;
			else
			{
				outputln("unsupported value for --build-mode");
				return false;
			}
			buildSettings.buildModeDeps = buildSettings.buildMode;
        }
		else if (option == "--config" || option == "-c")
        {
            if (!value)
            {
                outputln("missing value, expected ", option, "=<configuration>");
                return false;
            }
            buildSettings.configuration = value;
        }
		else if (option == "--jobs" || option == "-j")
		{
			if (!value)
            {
                outputln("missing value, expected ", option, "=<numThreads>");
                return false;
            }
			try
			{
				numThreads = to!int(value);
			}
			catch (Exception e)
			{
				outputln("invalid value, expected ", option, "=<numThreads>");
				return false;
			}
		}
		else if (option == "--output" || option == "-of")
		{
			if (!value)
            {
                outputln("missing value, expected ", option, "=<outputFileName>");
                return false;
            }
			import std.path;
			buildSettings.outputName = value;
			if (extension(buildSettings.outputName) == binaryExt ||
				extension(buildSettings.outputName) == staticLibraryExt ||
				extension(buildSettings.outputName) == dynamicLibraryExt)
			{
				buildSettings.outputName = stripExtension(buildSettings.outputName);
			}
		}
		else if (option == "--debug" || option == "-d")
		{
			if (!value)
            {
                outputln("missing value, expected ", option, "=<identifier>");
                return false;
            }
			errorln("not implemented");
		}
		else if (option == "--run")
		{
			runProject = true;
		}
		else if (option == "--")
		{
			if (!runProject)
				errorln("option '--' unexpected");
			runProjectArgs = args[i+1..$];
			break;
		}
        else if (option.startsWith("-"))
        {
            outputln("unknown option: ", option);
            return false;
        }
        else if (!buildSettings.buildTarget)
		{
			const string[] knownDubCommands =
			[
				"init",
				"run", /*"build",*/ "test", "generate", "describe", "clean", "dustmite",
				"fetch", "add", "remove", "upgrade",
				"add-path", "remove-path", "add-local", "remove-local",
				"list", "search",
				"add-override", "remove-override", "list-overrides",
				"clean-caches", "convert"
			];

			import std.algorithm : canFind, startsWith;

			if (canFind(knownDubCommands, arg))
				errorln("dub command detected, the correct usage is: cvbuild <buildDirectory> [dubPackage] [options]");

			buildSettings.buildTarget = arg;
		}
		else if (!buildSettings.dubPackage)
		{
			if (!arg.startsWith(":"))
				errorln("building cached packages is not implemented");

			buildSettings.dubPackage = arg;
		}
        else
        {
            outputln("unknown option: ", option);
            return false;
        }
    }

	import std.path;
	import std.file;

    if (!buildSettings.buildTarget)
    {
        outputln("usage: cvbuild <buildDirectory> [dubPackage] [options]");
        return false;
    }
	else if (buildSettings.buildTarget == "." || absolutePath(getcwd()) == absolutePath(buildSettings.buildTarget))
	{
        outputln("build directory cannot be the base folder");
        return false;
    }
	else if (buildSettings.buildTarget == ".dub")
	{
        outputln("build directory cannot be the .dub folder");
        return false;
    }
	else if (exists(buildSettings.buildTarget) && !isDir(buildSettings.buildTarget))
	{
		outputln("build directory expected, not a file");
        return false;
	}

	if (buildSettings.buildModeDeps == BuildMode.Auto)
		buildSettings.buildModeDeps = buildSettings.buildMode;
	return true;
}

// TODO: what does this do in unix?
string searchPath(string filename)
{
	import std.path;
	import std.file;

	if (!extension(filename))
		filename = setExtension(filename, "exe");

	if (isAbsolute(filename))
		return exists(filename) ? filename : null;

	if (exists(filename))
		return filename;

	import std.process;
	import std.algorithm;
	foreach (path; splitter(environment["PATH"], pathSeparator))
	{
		import std.path;
		string fullpath = buildPath(path, filename);

		if (exists(fullpath))
			return fullpath;
	}
	return null;
}

bool build(DubProject project, BuildConfiguration buildConfig, BuildSettings buildSettings)
{
	import std.path;
	import std.file;

	MonoTime startTime = MonoTime.currTime;
	const SysTime nullTime = SysTime(0);

	//DubProject main = project;
	//mainProject = main;

	string currentDir = "";
    string buildDir = buildPath(currentDir, buildSettings.buildTarget);
    string buildSettingsFile = buildPath(buildDir, "cvbuild.json");
	string commandsFile = buildPath(buildDir, "cvbuild_commands.log");
	string logPackageDepsFile = buildPath(buildDir, "cvbuild_package_deps.log");
	string logModuleDepsFile = buildPath(buildDir, "cvbuild_module_deps.log");

	if (cleanBuild)
    {
        outputln("cleaning: ", buildDir);
        cleanBuildDirectory(buildDir);
        return true;
    }
    else if (forceBuild)
	{
        outputln("forcing rebuild: ", buildDir);
		cleanBuild = true;
	}

	if (!exists(buildDir))
    {
        mkdir(buildDir);
        forceBuild = true;

        //write(buildSettingsFile, buildSettings.getJson());
    }
	else if (exists(buildSettingsFile) && !forceBuild)
	{
		// compare current build settings with previous build settings
		BuildSettings lastBuildSettings = BuildSettings.load(buildSettingsFile);
		if (buildSettings.changed(lastBuildSettings))
		{
			outputln("build settings changed, forcing rebuild");
			forceBuild = true;
			cleanBuild = true;

			write(buildSettingsFile, buildSettings.getJson());
		}
		else
		{
			// merge important cached data
			buildSettings.lastBuildTime = lastBuildSettings.lastBuildTime;
			buildSettings.compilerModifiedTime = lastBuildSettings.compilerModifiedTime;
		}
	}

	// check if compiler had changed
	string compilerPath = searchPath(buildSettings.compilerPath());
	if (!compilerPath)
		errorln("compiler not found: '", buildSettings.compilerPath(), "'");

	SysTime compilerModifiedTime = timeLastModified(compilerPath);
	if (!forceBuild && compilerModifiedTime != buildSettings.compilerModifiedTime)
	{
		outputln("compiler changed, forcing rebuild");
		forceBuild = true;
		cleanBuild = true;
	}

	if (!forceBuild)
	{
		string rootPackageName = getRootPackageName(buildSettings.dubPackage);
		string subPackageName = null;
		if (rootPackageName == project.name || !rootPackageName)
			subPackageName = getSubPackageName(buildSettings.dubPackage);

		foreach (pkg; project.byPackages(subPackageName, buildSettings.configuration))
		{
			SysTime dubConfigModified = timeLastModified(pkg.dubPath);
			if (dubConfigModified > buildSettings.lastBuildTime)
			{
				// TODO: rebuild only the dirty package and its dependencies
				outputln("package ", pkg.name, " changed, forcing rebuild");
				forceBuild = true;
				break;
			}
		}
	}

	// TODO: check timestamp of libs?

	if (cleanBuild)
		cleanBuildDirectory(buildDir);

	// check all relevant dub packages
	/*foreach (p; DubProject.allDubProjects.byValue)
    {
        if (timeLastModified(p.dubPath) > buildSettings.lastBuildTime)
        {
			outputln("project dependency changed, forcing rebuild");
            forceBuild = true;
            break;
        }
    }*/

	MonoTime startTimeCommands = MonoTime.currTime;
    //auto cont = prepareBuild(project, buildSettings, buildSettings.buildMode, buildSettings.configuration);
	Command[] commands = buildConfig.getCommands(buildSettings);
	//Command[] commands = cont.commands;//buildSettings.buildContext.commands;
	{
		Appender!string cmdStr;
		foreach (cmd; commands)
		{
			//outputln(cmd.args.join(" "));
			cmdStr ~= cmd.getArgs().join(" ");
			cmdStr ~= "\n";
		}
		write(commandsFile, cmdStr.data);
	}
	/*foreach (cmd; commands)
	{
		import std.algorithm;
		int[string] found;
		foreach (arg; cmd.args)
		{
			found.require(arg, 0);
			found[arg]++;
			//if (count(cmd.args, arg) > 1)
			//	found[arg]++;
		}

		bool foundmany = false;
		foreach (f, i; found)
		{
			if (i > 1)
			{
				foundmany = true;
				outputln(i, ": '", f, "'");
			}
		}

		if (foundmany)
			outputln(cmd.args.join(" "));
	}*/


    if (printTiming)
        outputln("cvbuild commands time: ", cast(long)((MonoTime.currTime-startTimeCommands).total!"hnsecs"*0.0001), "ms");

	MonoTime startTimeTasks = MonoTime.currTime;

	foreach (cmd; commands)
	{
		foreach (req; cmd.required)
			req.depends ~= cmd;
	}
	//Command[] dirtyCommands = forceBuild ? commands : getDirtyCommands(commands, buildSettings, buildSettings.lastBuildTime);
	Command[] dirtyCommands = getDirtyCommands(commands, buildSettings, buildSettings.lastBuildTime, forceBuild);

	/*if (dirtyCommands.length > 0 && dirtyCommands.length != commands.length)
	{
		if (buildSettings.buildMode == BuildMode.Module || buildSettings.buildModeDeps == BuildMode.Module)
		{
			outputln("forcing full rebuild due to buildMode=module, ", dirtyCommands.length, " != ", commands.length);
			forceBuild = true;
			dirtyCommands = commands;

			foreach (cmd; commands)
			{
				cmd.done = false;
				//cmd.forced = true;
			}
		}
	}*/

	if (printTiming)
        outputln("cvbuild dirty check time: ", cast(long)((MonoTime.currTime-startTimeTasks).total!"hnsecs"*0.0001), "ms");

	debug
	{
		// a hack to catch missing command dependencies: link commands should fail because input is missing
		import std.algorithm : reverse;
		reverse(dirtyCommands);
	}

	if (noBuild)
		return true;

	if (!runTasks(dirtyCommands, buildSettings.buildTarget))
		return false;

	buildSettings.lastBuildTime = Clock.currTime;
	buildSettings.compilerModifiedTime = compilerModifiedTime;
	write(buildSettingsFile, buildSettings.getJson());

	return true;
}

Command[] getDirtyCommands(Command[] commands, BuildSettings buildSettings, SysTime lastBuildTime, bool rebuildAll)
{
	import std.file;
	import std.path;

	import cvbuild.moduledeps;
	ModuleDep[ModuleFile] moduleDeps;

	ModuleFile[] allModuleFiles;
	ModuleFile[] dirtyModuleFiles;

	// gather module files and mark dirty ones
	foreach (Command cmd; commands)
	{
		allModuleFiles ~= cmd.moduleInputs;

		if (rebuildAll)
			continue;

		string workDir = cmd.workDir;
		foreach (inputModule; cmd.moduleInputs)
		{
			string input = buildNormalizedPath(workDir, inputModule.path);
			if (exists(input) && timeLastModified(input) <= lastBuildTime)
			{
				inputModule.dirty = false;
				continue;
			}
			dirtyModuleFiles ~= inputModule;
		}
	}

	// generate deps cache if it doesn't exist already
	if (!noModuleDepsResolve)
		ResolveDependencies(allModuleFiles, buildSettings, moduleDeps);

	if (rebuildAll)
		return commands;

	void markDirtyRecursively(ref ModuleFile moduleFile)
	{
		if (moduleFile.dirty)
			return;

		moduleFile.dirty = true;
		//outputln("mark dirty: ", moduleFile.name);

		foreach (dep; moduleDeps[moduleFile].dependants)
			markDirtyRecursively(dep);
	}

	if (dirtyModuleFiles.length > 0)
	{
		// only the changed files needs to be resolved again, dependants imports did not change
		if (!noModuleDepsResolve)
			ResolveDependencies(dirtyModuleFiles, buildSettings, moduleDeps);

		foreach (ModuleFile dirtyMod; dirtyModuleFiles)
		{
			dirtyMod.dirty = false; // need for recursion
			markDirtyRecursively(dirtyMod);
		}
	}

	// assume everything is done
	foreach (Command cmd; commands)
		cmd.done = true;

	foreach (Command cmd; commands)
	{
		string workDir = cmd.workDir;

		// check if command output exists
		bool dirtyOutput = false;
		foreach (output_; cmd.outputs)
		{
			string output = buildNormalizedPath(workDir, output_);
			if (exists(output))
				continue;

			dirtyOutput = true;

			if (printDirty)
				outputln("dirty (missing): ", output);
			else
				break;
		}

		// check if any of the object files have changed since last build time
		bool dirtyLinkage = false;
		foreach (input_; cmd.linkInputs)
		{
			string input = buildNormalizedPath(workDir, input_);
			if (exists(input) && timeLastModified(input) <= lastBuildTime)
				continue;

			dirtyLinkage = true;
			if (printDirty)
			{
				if (exists(input))
					outputln("dirty: ", input);
				else
					outputln("dirty (missing): ", input);
			}
			else
				break;
		}

		// check for dirty modules
		bool dirtyModules;
		foreach (inputModule; cmd.moduleInputs)
		{
			if (!inputModule.dirty)
				continue;

			dirtyModules = true;
			if (printDirty)
				outputln("dirty: ", inputModule.name, " (", cmd.name, ")");
			else
				break;
		}

		if (!dirtyOutput && !dirtyLinkage && !dirtyModules)
			continue;

		foreach (req; cmd.depends)
			req.done = false;
		cmd.done = false;
	}

	Command[] dirtyCommands;
	foreach (Command cmd; commands)
	{
		if (cmd.done)
			continue;
		dirtyCommands ~= cmd;
	}

	return dirtyCommands;
}

void cleanBuildDirectory(string buildDir)
{
	import std.file;
	import std.path;

    if (!exists(buildDir))
		return;

	foreach (DirEntry entry; dirEntries(buildDir, SpanMode.shallow))
	{
		if (entry.isDir())
		{
			rmdirRecurse(entry);
			continue;
		}

		std.file.remove(entry.name);
	}
}