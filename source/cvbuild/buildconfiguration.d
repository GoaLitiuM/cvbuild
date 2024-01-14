module cvbuild.buildconfiguration;

import cvbuild.buildsettings;
import cvbuild.dubpackage;
import cvbuild.globals;
import cvbuild.helpers;
import cvbuild.compiler;
import cvbuild.serialization;
import cvbuild.environment;

import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.format;
import std.conv : to;
import std.string;

T[] uniqueOnly(T)(T[] arr)
{
	bool[T] newarr;

	foreach (ref a; arr)
		newarr[a] = true;

	if (newarr.keys.length == arr.length)
		return arr;
	assert(newarr.keys.length < arr.length);
	return newarr.keys;
}

struct SourceFile
{
	string path;
	string file;

	string fullPath()
	{
		return buildNormalizedPath(path, file);
	}
}

class BuildConfiguration
{
	// options to control build command generation
	private bool separateLinking = true; // ideally true, but could be switched to false for simple projects
	private bool combineObjects = false; // ideally we want this false for partial package rebuilds, but it has issues with some projects
	private bool objectDirectoryHierarchy = true; // ideally true so object file naming collisions could be avoided

	private bool objectImportNaming; // set when object files are named after the packages (std/format.d -> std.format.obj)
	private bool objectPathNaming; // set when object files directory hierarchy is kept in build directory (std/format.d -> std/format.obj)
	private string outputBasePath;
	private size_t maxPackageUnitSize = 40; // arbitrary number, varies based on the complexity of the modules

	string path;
	string relPath;
	string buildName;
	string subPackage;
	string configuration;
	BuildMode buildMode;
	//bool isDep;
	BuildConfiguration parent;
	static Compiler compiler;

	struct BuildConfigurationKey
	{
		string buildName;
		string configuration;

		bool opEquals(ref const BuildConfigurationKey other) const
		{
			return buildName == other.buildName && configuration == other.configuration;
		}
	}
	BuildConfiguration[BuildConfigurationKey] configuredBuilds;

	static BuildConfiguration create(DubProject project, BuildSettings buildSettings, string path = null)
	{
		if (!compiler)
		{
			// TODO: determine compiler from given path
			if (buildSettings.compiler == "dmd" || buildSettings.compiler == "ldmd2")
				compiler = new DmdCompiler(buildSettings.compiler);
			else if (buildSettings.compiler == "ldc2")
				compiler = new LdcCompiler(buildSettings.compiler);
			else
				outputln("unsupported compiler for buildOption: ", buildSettings.compiler);
		}

		string subPackage = getSubPackageName(buildSettings.dubPackage);
		string buildName = project.rootPackage ? (project.rootPackage ~ ":" ~ project.name) : (project.name ~ (subPackage ? (":" ~ subPackage) : ""));
		string configuration = buildSettings.configuration;
		BuildConfiguration buildConfig = new BuildConfiguration();

		buildConfig.buildMode = buildSettings.buildMode;
		buildConfig.path = dirName(project.dubPath).trimDot;
		buildConfig.buildName = buildName;
		buildConfig.subPackage = project.rootPackage ? null : subPackage;

		// explicitly requested configuration is used so dependencies depending on root package gets referenced properly (mainly affects cyclicDependency test)
		buildConfig.configuredBuilds[BuildConfigurationKey(buildName, configuration)] = buildConfig;
		if (configuration)
			buildConfig.configuration = configuration;
		else
			buildConfig.configuration = detectConfiguration(project, buildSettings, path, !!buildConfig.parent);

		buildConfig.configure(project, buildSettings);

		return buildConfig;
	}

	private BuildConfiguration create(DubProject project, BuildSettings buildSettings, string path, string subPackage, string configuration)
	{
		string buildName = project.rootPackage ? (project.rootPackage ~ ":" ~ project.name) : (project.name ~ (subPackage ? (":" ~ subPackage) : ""));

		BuildConfiguration buildConfig = new BuildConfiguration();

		// FIXME: path could point to root package, so ignore it
		if (path != dirName(project.dubPath))
			outputln(buildName, " path corrected");
		path = dirName(project.dubPath);

		buildConfig.buildMode = buildSettings.buildModeDeps;
		buildConfig.path = path;
		//buildConfig.isDep = true;
		buildConfig.parent = this;
		buildConfig.subPackage = subPackage;
		buildConfig.buildName = buildName;

		// configuration is autodetected afterwards so unconfigured projects do not get built twice.
		// this mainly affects dependency to main package from subPackages so the dependency to library configurations
		// gets matched to application configuration of the main package (see cyclicDependency test).
		BuildConfiguration* existingBuildConfig = BuildConfigurationKey(buildName, configuration) in configuredBuilds;
		if (existingBuildConfig)
			return *existingBuildConfig;

		configuredBuilds[BuildConfigurationKey(buildName, configuration)] = buildConfig;
		if (configuration)
			buildConfig.configuration = configuration;
		else
			buildConfig.configuration = detectConfiguration(project, buildSettings, path, !!buildConfig.parent);

		buildConfig.configuredBuilds = configuredBuilds;
		buildConfig.configure(project, buildSettings);

		return buildConfig;
	}

	private BuildConfiguration[] buildDependencies;
	ModuleFile[] moduleFiles;
	string[] objFiles;
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] versions;
	string[] debugVersions;
	string[] commonFlags;
	string[] linkFlags;
	string[] linkFiles;
	string[] outputs;
	string[] importPaths;
	string[] stringImportPaths;
	string outputPath;
	string targetName;
	TargetType targetType;
	string targetPath; // mostly ignored for now

	private void configure(DubProject project, BuildSettings buildSettings)
	{
		relPath = path;

		if (printConfiguration)
			outputln("configuring ", buildName, ", configuration: ", configuration);

		targetName = getPlatformFlags!"targetName"(project, buildSettings, configuration, subPackage, false);
		if (!targetName/* || isDep*/)
			targetName = buildName.replace(":", "_");
		if (!parent && buildSettings.outputName)
			targetName = buildSettings.outputName;

		targetPath = getPlatformFlags!"targetPath"(project, buildSettings, configuration, subPackage);
		if (parent)
			targetPath = ""; // i don't think dependencies should have custom target paths?

		// target type
		targetType = getPlatformFlags!"targetType"(project, buildSettings, configuration, subPackage);
		if (targetType == TargetType.autodetect)
		{
			if (configuration == "application")
				targetType = TargetType.executable;
			else if (configuration == "library")
				targetType = TargetType.library;
			else if (parent)
				targetType = TargetType.library;
			else
				targetType = TargetType.executable;
		}
		if (targetType == TargetType.library)
		{
			//if (!isDep)
			//	errorln("main package cannot be library");
			if (parent)
				targetType = TargetType.sourceLibrary;
		}
		if (parent && targetType == TargetType.dynamicLibrary)
		{
			warningln("building dynamicLibrary as staticLibrary");
			targetType = TargetType.staticLibrary;
		}
		/*if (isDep && targetType == TargetType.executable)
		{
			errorln("dependency ", buildName, " is executable");
		}*/

		string buildTargetPath = buildSettings.buildTarget;
		if (isAbsolute(path) && objectDirectoryHierarchy)
		{
			relPath = null;
			buildTargetPath = absolutePath(buildTargetPath);
		}

		string outputFilename;
		if (targetType == TargetType.executable)
			outputFilename = targetName ~ binaryExt;
		else if (targetType == TargetType.library || targetType == TargetType.staticLibrary || targetType == TargetType.sourceLibrary)
		{
			// static library files should be left in the build directory
			outputFilename = targetName ~ staticLibraryExt;
		}
		else if (targetType == TargetType.dynamicLibrary)
			outputFilename = targetName ~ dynamicLibraryExt;

		if (targetType == TargetType.library || targetType == TargetType.staticLibrary || targetType == TargetType.sourceLibrary)
		{
			outputPath = buildNormalizedPath(buildTargetPath, targetPath, outputFilename);
		}
		else
			outputPath = buildNormalizedPath(/*relPath,*/ targetPath, outputFilename); // executables and dynamic libraries should be placed to working directory


		dflags = getPlatformFlags!"dflags"(project, buildSettings, configuration, subPackage);
		lflags = getPlatformFlags!"lflags"(project, buildSettings, configuration, subPackage);
		commonFlags = getCommonFlags(buildSettings.arch);

		libs = getPlatformFlags!"libs"(project, buildSettings, configuration, subPackage);
		versions = getPlatformFlags!"versions"(project, buildSettings, configuration, subPackage);
		debugVersions = getPlatformFlags!"debugVersions"(project, buildSettings, configuration, subPackage);

		if (targetType != TargetType.none)
		{
			foreach (importPath; getPlatformFlags!"importPaths"(project, buildSettings, configuration, subPackage, false))
			{
				string path = buildNormalizedPath(path, importPath);
				if (exists(path))
					importPaths ~= path;
			}

			foreach (stringImportPath; getPlatformFlags!"stringImportPaths"(project, buildSettings, configuration, subPackage, false))
			{
				string path = buildNormalizedPath(path, stringImportPath);
				if (exists(path))
					stringImportPaths ~= path;
			}
		}

		if (parent)
			inheritFromParent(parent);

		configureDependencies(project, buildSettings);


		// gather all source files
		string[] excludedFiles = getPlatformFlags!"excludedSourceFiles"(project, buildSettings, configuration, subPackage, false);
		string mainSourceFileName = getPlatformFlags!"mainSourceFile"(project, buildSettings, configuration, subPackage);
		if (targetType != TargetType.executable && mainSourceFileName)
			excludedFiles ~= mainSourceFileName;

		SourceFile[] sourceFiles = getSourceFiles(project, buildSettings, excludedFiles);
		foreach (sourceFile; getPlatformFlags!"sourceFiles"(project, buildSettings, configuration, subPackage, false))
		{
			if (extension(sourceFile) == ".res")
			{
				// windows resource files should be treated as linkage
				objFiles ~= buildNormalizedPath(path, sourceFile);//relativePath(sourceFile, path);
				continue;
			}
			else if (extension(sourceFile) == objectExt)
			{
				objFiles ~= buildNormalizedPath(path, sourceFile);
				continue;
			}
			else if (extension(sourceFile) == staticLibraryExt || extension(sourceFile) == dynamicLibraryExt)
			{
				linkFiles ~= buildNormalizedPath(path, sourceFile);
				continue;
			}

			// figuring out module names for sourceFiles is hard,
			// assume the first directory in path is a source directory and guess the module name from rest

			string p = buildNormalizedPath(relPath, sourceFile);
			string sourcePath = dirName(p).trimDot();
			string file;
			if (sourcePath)
			{
				auto ind = sourcePath.indexOf(dirSeparator);
				if (ind != -1)
					sourcePath = sourcePath[0..ind+1];

				if (!sourcePath.endsWith(dirSeparator))
					sourcePath ~= dirSeparator;

				file = p[sourcePath.length..$];
			}
			else
				file = p;
			//string file = baseName(sourceFile);
			sourceFiles ~= SourceFile(sourcePath, file);
		}

		if (mainSourceFileName && targetType == TargetType.executable)
		{
			// make sure mainSourceFile is included
			string sourcePath = dirName(buildNormalizedPath(relPath, mainSourceFileName));
			string file = baseName(mainSourceFileName);
			SourceFile mainSourceFile = SourceFile(sourcePath, file);

			bool alreadyIncluded = false;
			foreach (sourceFile; sourceFiles)
			{
				if (sourceFile.fullPath == mainSourceFile.fullPath)
				{
					alreadyIncluded = true;
					break;
				}
			}

			if (!alreadyIncluded)
				sourceFiles ~= mainSourceFile;
		}

		// source files to modules
		foreach (sourceFile; sourceFiles)
		{
			string fullPath = sourceFile.fullPath;
			if (objectDirectoryHierarchy)
			{
				fullPath = relativePath(fullPath, path);
				assert(!isAbsolute(fullPath));
			}

			string moduleName = stripExtension(sourceFile.file).replace(dirSeparator, ".");
			moduleFiles ~= new ModuleFile(moduleName, fullPath, isAbsolute(path) ? path : null);
		}

		import std.algorithm.sorting;
		sourceFiles = sort!((a, b) => a.fullPath < b.fullPath)(sourceFiles).release;


		// build options
		int debugLevel = 0;
		BuildOption[] buildOptions = getPlatformFlags!"buildOptions"(project, buildSettings, configuration, subPackage);
		foreach (opt; buildOptions)
		{
			if (opt == BuildOption.debugMode)
			{
				// special case: the order with -debug and -debug=level matters, so this must be handled after debugVersions
				debugLevel = 1;
				continue;
			}

			auto args = opt in compiler.options;
			if (args)
			{
				dflags ~= *args;
				continue;
			}
		}


		targetName = getPlatformFlags!"targetName"(project, buildSettings, configuration, subPackage, false);
		if (!targetName/* || isDep*/)
			targetName = buildName.replace(":", "_");


		// lflags are always passed with -L=
		foreach (i, lflag; lflags)
			lflags[i] = "-L=" ~ expandDubBuildVariables(lflag, project, buildSettings, buildSettings.dubVariables);


		if (!parent && targetType == TargetType.sourceLibrary)
			errorln("cannot build main package with targetType sourceLibrary");


		if (targetType == TargetType.library || targetType == TargetType.staticLibrary || targetType == TargetType.sourceLibrary)
		{
			if (moduleFiles.length > 0 || objFiles.length > 0)
				outputs ~= outputPath;
		}

		foreach (dep; buildDependencies)
			inheritFromChild(dep);

		// build flags
		foreach (ver; versions)
			dflags ~= format!"%s=%s"(compiler.switches["-version"], ver);
		foreach (ver; debugVersions)
		{
			uint integer = 0;
			try integer = to!uint(ver); catch(Exception) { }
			if (integer > 0)
				debugLevel = max(debugLevel, integer);
			else
				dflags ~= format!"%s=%s"(compiler.switches["-debug"], ver);
		}
		foreach (i; importPaths)
			dflags ~= "-I=" ~ i;
		foreach (importPath; stringImportPaths)
			dflags ~= format!"%s=%s"(compiler.switches["-J"], importPath);

		if (debugLevel == 1)
			dflags ~= compiler.options[BuildOption.debugMode][0];
		else if (debugLevel > 1)
			dflags ~= format!"%s=%d"(compiler.switches["-debug"], debugLevel);


		// linkage
		//foreach (lib; libs)
		//	linkFiles ~= /*"-L=" ~ */lib ~ staticLibraryExt;
	}

	SourceFile[] getSourceFiles(DubProject project, BuildSettings buildSettings, string[] excludedFiles)
	{
		SourceFile[] sourceFiles;

		string projectPath = path;
		if (projectPath && !projectPath.endsWith(dirSeparator))
			projectPath ~= dirSeparator;

		string[] sourcePaths;
		//if (targetType != TargetType.none)
			sourcePaths = getPlatformFlags!"sourcePaths"(project, buildSettings, configuration, subPackage, false);

		foreach (sourcePath; sourcePaths)
		{
			string fullPath = buildNormalizedPath(path, sourcePath);
			if (!exists(fullPath))
			{
				//if (printTrivialWarnings)
				//	outputln("warning: source path '", normPath ,"' does not exist.");
				continue;
			}

			foreach (string sourceFile; dirEntries(fullPath, SpanMode.depth))
			{
				string ext = extension(sourceFile);
				if (ext != ".d" && ext != ".di" && ext != ".dpp")
					continue;

				string normSourceFile = sourceFile[projectPath.length..$];
				if (shouldExclude(normSourceFile.replace(dirSeparator, "/"), excludedFiles))
				{
					//outputln("excluded: ", sourceFile);
					continue;
				}
				/*string file = normSourceFile;
				if (fullPath)
					file = sourceFile[fullPath.length+1..$];
				sourceFiles ~= SourceFile(fullPath, file);*/
				sourceFiles ~= SourceFile(fullPath, sourceFile[fullPath.length+1..$]);
			}
		}
		return sourceFiles;
	}

	private static string detectConfiguration(DubProject project, BuildSettings buildSettings, string path, bool isDependency)
	{
		string configuration = project.getDefaultConfiguration(buildSettings, true);
		if (!configuration)
		{
			if (isDependency)
				return "library";
			else
			{
				if (isApplication(buildNormalizedPath(dirName(project.dubPath)), project.name))
					return "application";
				else
					return "library";
			}
		}
		return configuration;
	}

	static string[] getCommonFlags(string arch)
	{
		string[] commonFlags = ["-vcolumns"];
		//commonFlags ~= "-L=/FASTFAIL";
		if (arch == "x86_64")
			commonFlags ~= ["-m64"/*, "-L=/SUBSYSTEM:CONSOLE"*/];
		else if (arch == "x86")
			commonFlags ~= ["-m32"/*, "-L=/SUBSYSTEM:CONSOLE"*/];
		else if (arch == "x86mscoff")
			commonFlags ~= ["-m32mscoff"/*, "-L=/SUBSYSTEM:CONSOLE"*/];
		else
			outputln("unsupported arch: ", arch);
		return commonFlags;
	}

	private void configureDependencies(DubProject project, BuildSettings buildSettings)
	{
		DubDependency[string] dependencies = project.getDependencies(subPackage, configuration);

		//string[] inherited_lflags;
		foreach (depName, dep; dependencies)
		{
			assert(dep.dubPackage, "dependency package is missing: " ~ depName);
			string depPath = dirName(dep.dubPackage.dubPath).trimDot();
			string depSubPackage = dep.dubPackage.rootPackage ? null : dep.subPackage;
			//string depConfiguration = project.subConfigurations.get(dep.dubPackage.name, null); // FIXME: use depName?
			string depConfiguration = project.getSubConfiguration(depName, configuration);

			BuildConfiguration depConfig = BuildConfiguration.create(dep.dubPackage, buildSettings, depPath, depSubPackage, depConfiguration);
			//outputln(depName, " : ", depSubPackage, " <-> dep ", depConfig.buildName);
			buildDependencies ~= depConfig;

			//depConfig.inheritFromParent(this);
		}
	}

	// inherits configurable values from parent/dependant
	private void inheritFromParent(BuildConfiguration parent)
	{
		versions ~= "Have_" ~ parent.buildName.replace("-", "_").replace(":", "_");

		//if (parent.targetType != TargetType.none)
		//if (targetType != TargetType.none)
		{
			stringImportPaths ~= parent.stringImportPaths;
			versions ~= parent.versions;
			debugVersions ~= parent.debugVersions;
		}



		stringImportPaths = uniqueOnly(stringImportPaths);
		versions = uniqueOnly(versions);
		debugVersions = uniqueOnly(debugVersions);
	}

	// inherits configurable values from child/dependency
	private void inheritFromChild(BuildConfiguration child)
	{

		//if (child.targetType == TargetType.library || child.targetType == TargetType.staticLibrary || child.targetType == TargetType.sourceLibrary)
		if (child.targetType != TargetType.executable && child.targetType != TargetType.dynamicLibrary)
		{
			linkFiles ~= child.outputs;
			linkFiles ~= child.linkFiles;
			//child.linkFiles = null;
			linkFiles = uniqueOnly(linkFiles);
			libs ~= child.libs;
			libs = uniqueOnly(libs);
			//outputln(buildName, " inputs: ", inputs);
		}
		/*else
		{
			linkFiles ~= child.linkFiles;
			child.linkFiles = null;
			linkFiles = uniqueOnly(linkFiles);
		}*/

		versions ~= "Have_" ~ child.buildName.replace("-", "_").replace(":", "_");

		//if (child.targetType != TargetType.none)
		//if (targetType != TargetType.none)
		{
			importPaths ~= child.importPaths;
			stringImportPaths ~= child.stringImportPaths;
			dflags ~= child.dflags;

			//lflags_inherit ~= child.lflags_inherit;
			//linkFiles ~= child.linkFiles;
			versions ~= child.versions;
			debugVersions ~= child.debugVersions;
		}


		importPaths = uniqueOnly(importPaths);
		stringImportPaths = uniqueOnly(stringImportPaths);
		dflags = uniqueOnly(dflags);
		versions = uniqueOnly(versions);
		debugVersions = uniqueOnly(debugVersions);
	}

	Command[] getCommands(BuildSettings buildSettings)
	{
		Command[] commands;
		foreach (buildConfig; configuredBuilds.byValue)
		{
			//outputln("commands for ", buildConfig.buildName, " with configuration: ", buildConfig.configuration);
			commands ~= buildConfig.generateCommands(buildSettings);
		}

		foreach (cmd; commands)
		{
			string[] inputs = cmd.getInputFiles();
			//outputln("_ ", cmd.name, " inputs: ", cmd.inputs, " output: ", cmd.output);
			foreach (other; commands)
			{
				if (other == cmd)
					continue;

				//outputln("______ ", other.name, " output: ", other.output);
				foreach (output; other.outputs)
				{
					if (canFind(inputs, output))
					{
						//outputln(cmd.name, " added req to ", other.name, " because: ", other.output);
						cmd.required ~= other;
						break;
					}
				}
			}
		}

		foreach (cmd; commands)
		{
			cmd.required = uniqueOnly(cmd.required);

			string[] required;
			foreach (other; cmd.required)
				required ~= other.name;

			//outputln(cmd.name, " depends on ", required);
		}

		return commands;
	}

	private Command[] generateCommands(BuildSettings buildSettings)
	{
		Command[] commands;

		string buildTargetPath = buildSettings.buildTarget;
		if (isAbsolute(path) && objectDirectoryHierarchy)
			buildTargetPath = absolutePath(buildTargetPath);

		if (targetType == TargetType.none)
			return null;

		bool isLibrary = targetType == TargetType.library || targetType == TargetType.staticLibrary || targetType == TargetType.sourceLibrary;
		if (targetType == TargetType.dynamicLibrary)
			linkFlags ~= compiler.switches["-shared"];
		else if (isLibrary)
			linkFlags ~= compiler.switches["-lib"];

		string buildNameRoot = buildName;
		size_t dind = buildNameRoot.indexOf(":");
		if (dind != -1)
			buildNameRoot = buildName[0..dind];

		string objectPath = buildNormalizedPath(buildTargetPath, buildNameRoot);
		if (!exists(objectPath))
			mkdir(objectPath);
		objectPath = buildNormalizedPath(buildTargetPath, buildName.replace(":", dirSeparator));
		if (!exists(objectPath))
			mkdir(objectPath);

		if (buildMode == BuildMode.Module)
		{
			if (!separateLinking)
			{
				//outputln("combined linking not supported with --buildMode=module");
				separateLinking = true;
			}
			if (!combineObjects)
			{
				//outputln("combined object files not supported with --buildMode=module");
				combineObjects = true;
			}

			dflags ~= compiler.switches["-c"]; // compile only
			//dflags ~= compiler.switches["-allinst"];
			foreach (sourceFile; moduleFiles)
				commands ~= addBuildCommand(buildName ~ ": " ~ sourceFile.name, sourceFile.path, [sourceFile], stripExtension(sourceFile.path).replace(".", "__").replace(":", "__"), objectPath);
		}
		else if (buildMode == BuildMode.Project || buildMode == BuildMode.Package)
		{
			string fullName = buildName; // targetName?

			class SourcePackage
			{
				ModuleFile[] moduleFiles;
			}
			SourcePackage[string] packages; // key: project.package

			if (separateLinking)
			{
				dflags ~= compiler.switches["-c"];
				//dflags ~= compiler.switches["-allinst"];

				if (buildSettings.platform == "linux")
				{
					//dflags ~= "-fPIC";
					//linkFlags ~= "-fPIC";
				}
			}

			if (buildMode == BuildMode.Project)
			{
				// project is basically a single package build
				maxPackageUnitSize = size_t.max;
				if (moduleFiles.length > 0)
				{
					SourcePackage pkg = packages.require(fullName, new SourcePackage);
					pkg.moduleFiles ~= moduleFiles;
				}
			}
			else if (buildMode == BuildMode.Package)
			{
				foreach (mod; moduleFiles)
				{
					// module names may not map to correct package
					//assert(!isAbsolute(mod.path), mod.path ~ " is not relative");

					string moduleName = mod.name;
					string packageName = null;
					assert(moduleName);
					if (moduleName)
					{
						string modulePackageName = moduleName;
						size_t mind = modulePackageName.lastIndexOf('.');
						if (mind == -1)
							modulePackageName = null;
						else
							modulePackageName = modulePackageName[0..mind];

						if (modulePackageName)
							packageName = fullName ~ "." ~ modulePackageName;
					}

					if (!packageName)
						packageName = fullName;

					SourcePackage pkg = packages.require(packageName, new SourcePackage);
					pkg.moduleFiles ~= mod;

					//outputln(packageName, ": ", mod.path);
				}
				outputln(buildName, ": prepared ", packages.length, " packages, total of ", moduleFiles.length, " modules");
			}

			if (separateLinking)
			{
				if (!combineObjects)
				{
					if (objectDirectoryHierarchy)
					{
						dflags ~= compiler.switches["-op"];
						objectPathNaming = true;
					}
					else if (compiler.type == CompilerType.LDC2)
					{
						dflags ~= compiler.switches["-oq"];
						objectImportNaming = true;
					}

					outputBasePath = buildNormalizedPath(buildTargetPath, targetPath, targetName);
					//dflags ~= compiler.switches["-op"]; // does not work with absolute paths
					dflags ~= compiler.switches["-od"] ~ "=" ~ outputBasePath;
					objectPath = null;
				}

				foreach (packageName, pkg; packages)
				{
					// TODO: implement a grouping strategy to spread complex/large modules across the build units in order to even the load
					string outputName = packageName.replace(".", "__").replace(":", "__");

					if (pkg.moduleFiles.length > maxPackageUnitSize)
					{
						import std.math;
						size_t total = cast(size_t)ceil(cast(float)pkg.moduleFiles.length/maxPackageUnitSize);

						for (size_t start=0, i=0; start<pkg.moduleFiles.length; i++)
						{
							size_t end = min(pkg.moduleFiles.length, start + maxPackageUnitSize);
							ModuleFile[] files = pkg.moduleFiles[start..end];



							string workName = packageName;
							if (files.length == 1)
								workName = packageName ~ ": " ~ files[0].name;
							else
								workName = packageName ~ " (" ~ to!string(i+1) ~ "/" ~ to!string(total) ~ ")";

							commands ~= addBuildCommand(workName, packageName, files, outputName ~ "__" ~ to!string(i), objectPath);

							start = end;
						}
					}
					else
						commands ~= addBuildCommand(packageName, packageName, pkg.moduleFiles, outputName, objectPath);
				}

				//foreach (cmd; commands)
				//	cmd.required = commandDeps;
			}
			else
			{
				if (compiler.type == CompilerType.LDC2)
				{
					// very confusing: DMD outputs all files relative to -od,
					// but LDC only outputs object files to -od, ignoring it for final output -of

					outputBasePath = buildNormalizedPath(buildTargetPath, targetPath, targetName);
					dflags ~= compiler.switches["-od"] ~ "=" ~ outputBasePath;
				}

				ModuleFile[] allModuleFiles;
				foreach (packageName, pkg; packages)
					allModuleFiles ~= pkg.moduleFiles;

				if (allModuleFiles.length > 0)
				{
					Command cmd = addBuildLinkCommand(fullName, fullName, allModuleFiles, outputPath, objectPath);
					//if (targetType == TargetType.executable || targetType == TargetType.dynamicLibrary)
					//	cmd.required = commandsDeps;
					commands ~= cmd;
				}
			}

		}
		else
			assert(0, "not implemented");

		if (moduleFiles.length > 0 || objFiles.length > 0)
		{
			//if (debugLevel > 0) // not sure if this affects linking??
			//	lflags ~= compilerOptions[BuildOption.debugMode][0];
			if (separateLinking)
			{
				Command linkcmd = addLinkCommand(relativePath(outputPath), objFiles, outputPath);

				//if (targetType == TargetType.executable || targetType == TargetType.dynamicLibrary)
				//	linkcmd.required = commands ~ commandsDeps;
				//else
					linkcmd.required = commands;

				commands ~= linkcmd;
			}
		}

		return commands;
	}

	private string getModuleObjectName(ModuleFile moduleFile, string packageName)
	{
		if (objectImportNaming)
		{
			string moduleName = moduleFile.name;

			if (moduleName == "package")
				moduleName = packageName;
			else if (moduleName.endsWith(".package"))
				moduleName = moduleName[0..$-".package".length];

			return moduleName ~ objectExt;
		}
		else if (objectPathNaming)
		{
			return setExtension(moduleFile.path.idup, objectExt);
		}
		else
			return setExtension(baseName(moduleFile.path).idup, objectExt);
	}

	private Command addBuildCommand(string name, string packageName, ModuleFile[] moduleFiles, string objFile, string objectPath)
	{
		Command cmd = new Command();
		if (!relPath && path)
			cmd.workDir = path;

		string objFileAdjusted = buildPath(objectPath, objFile ~ objectExt);
		string objFilePath = buildPath(outputBasePath, objFileAdjusted);

		cmd.name = name;//packageFullName;
		cmd.packageName = packageName;//packageName;

		cmd.args ~= compiler.path;

		foreach (moduleFile; moduleFiles)
		{
			string path = moduleFile.path;//buildPath(path, moduleFile.path);
			//cmd.inputs ~= absolutePath(path, cmd.workDir ? cmd.workDir : getcwd());
			//cmd.args ~= path;
			cmd.moduleInputs ~= moduleFile;
			if (!combineObjects)
			{
				assert(extension(path) == ".d");
				string opath = relativePath(buildNormalizedPath(outputBasePath, objectPath, getModuleObjectName(moduleFile, packageName)));
				objFiles ~= opath;
				cmd.outputs ~= absolutePath(opath);
			}
		}

		cmd.args ~= commonFlags;
		cmd.args ~= dflags;
		//if (buildMode == BuildMode.Project)
		//	cmd.args ~= lflags;
		//
		if (combineObjects)
		{
			cmd.args ~= "-of=" ~ objFileAdjusted;
			objFiles ~= objFilePath;
			cmd.outputs ~= absolutePath(objFilePath);
		}
		//else
		//	cmd.output = absolutePath(objFilePath);


		return cmd;
	}

	private Command addBuildLinkCommand(string name, string packageName, ModuleFile[] moduleFiles, string outputFile, string objectPath)
	{
		Command cmd = new Command();
		if (!relPath && path)
			cmd.workDir = path;
		cmd.name = name;//packageFullName;
		cmd.packageName = packageName;//packageName;

		cmd.args ~= compiler.path;

		foreach (moduleFile; moduleFiles)
		{
			string path = moduleFile.path;
			//cmd.inputs ~= absolutePath(path);
			//cmd.args ~= path;
			cmd.moduleInputs ~= moduleFile;
		}

		if (targetType == TargetType.executable || targetType == TargetType.dynamicLibrary)
		{
			foreach (lib; libs)
				cmd.linkInputsSystem ~= /*"-L=" ~ */lib ~ staticLibraryExt;

			foreach (link; linkFiles)
			{
				cmd.args ~= relativePath(link, cmd.workDir ? cmd.workDir : getcwd());
				cmd.linkInputs ~= absolutePath(link);
			}
		}

		cmd.args ~= commonFlags;
		cmd.args ~= dflags;
		cmd.args ~= lflags;
		cmd.args ~= linkFlags;
		cmd.args ~= "-of=" ~ outputFile;

		cmd.outputs ~= absolutePath(outputFile);

		return cmd;
	}

	private Command addLinkCommand(string name, string[] objFiles, string outputPath)
	{
		Command linkcmd = new Command();
		//if (!relPath && path)
		//	linkcmd.workDir = path;

		linkcmd.args ~= compiler.path;
		if (targetType == TargetType.executable || targetType == TargetType.dynamicLibrary)
		{
			foreach (lib; libs)
				linkcmd.linkInputsSystem ~= /*"-L=" ~ */lib ~ staticLibraryExt;

			// consume linkage
			foreach (link; linkFiles)
			{
				//linkcmd.args ~= relativePath(link, linkcmd.workDir ? linkcmd.workDir : getcwd());
				linkcmd.linkInputs ~= absolutePath(link);
			}
		}

		//linkcmd.args ~= objFiles;
		linkcmd.args ~= commonFlags;
		linkcmd.args ~= lflags;
		linkcmd.args ~= linkFlags;
		linkcmd.args ~= "-of=" ~ relativePath(outputPath, linkcmd.workDir ? linkcmd.workDir : getcwd());

		foreach (obj; objFiles)
			linkcmd.linkInputs ~= absolutePath(obj);

		linkcmd.outputs ~= absolutePath(outputPath);
		linkcmd.name = name;

		return linkcmd;
	}
}
