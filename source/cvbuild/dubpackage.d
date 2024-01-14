module cvbuild.dubpackage;

import cvbuild.globals;
import cvbuild.buildsettings;
import cvbuild.helpers;
import cvbuild.dub.json;
import cvbuild.dub.sdl;
import cvbuild.serialization;

import asdf;

import std.path;
import std.file;
import std.array;

enum BuildRequirement
{
	allowWarnings,
	silenceWarnings,
	disallowDeprecations,
	silenceDeprecations,
	disallowInlining,
	disallowOptimization,
	requireBoundsCheck,
	requireContracts,
	relaxProperties,
	noDefaultFlags,
}

enum BuildOption
{
	debugMode,
	releaseMode,
	coverage,
	debugInfo,
	debugInfoC,
	alwaysStackFrame,
	stackStomping,
	inline,
	noBoundsCheck,
	optimize,
	profile,
	profileGC,
	unittests,
	verbose,
	ignoreUnknownPragmas,
	syntaxOnly,
	warnings,
	warningsAsErrors,
	ignoreDeprecations,
	deprecationWarnings,
	deprecationErrors,
	property,
	betterC,
}

enum TargetType
{
	autodetect,
	none,
	executable,
	library,
	sourceLibrary,
	staticLibrary,
	dynamicLibrary
}

struct DubConfiguration
{
	static DubConfiguration deserialize(Asdf data)
	{
		return deserializeMembers!(DubConfiguration, true)(data);
	}

	string name;
	string[] platforms;

	mixin BuildSettingsMixin;
}

struct DubBuildType
{
	private this(BuildOption[] defaultOptions, string[] defaultDflags = null)
	{
		buildOptions[null] = defaultOptions;
		dflags[null] = defaultDflags;
	}

	static DubBuildType deserialize(Asdf data)
	{
		return deserializeMembers!(DubBuildType, true)(data);
	}

	mixin BuildSettingsMixin;

	private @serializationIgnore DubDependency[string] dependencies;
	private @serializationIgnore TargetType targetType;
	private @serializationIgnore string targetName;
	private @serializationIgnore string targetPath;
	private @serializationIgnore string workingDirectory;
	private @serializationIgnore string[string] subConfigurations;
}

class DubSubPackage
{
	@serializationIgnore DubProject dubPackage;

	this() { }
	this(string path)
	{
		this.name = baseName(path);
		this.path = path;
	}
	this(string name, string path)
	{
		this.name = name;
		this.path = path;
	}

	static DubSubPackage deserialize(Asdf data)
	{
		if (data.kind() == Asdf.Kind.string)
		{
			string path = asdf.deserialize!string(data);
			return new DubSubPackage(path);
		}
		else
			return deserializeMembers!(DubSubPackage, true)(data);
	}

	string name;
	string path; // should probably be ignored?

	DubConfiguration[] configurations;
	DubBuildType[string] buildTypes;
	mixin BuildSettingsMixin;
}

class DubDependency
{
	@serializationIgnore DubProject dubPackage;
	@serializationIgnore string subPackage;
	//@serializationIgnore bool isInternalSubPackage; // set when dubPackage points to root package
	@serializationIgnore bool found;

	this() { }
	this(string version_)
	{
		this.version_ = version_;
	}

	static DubDependency deserialize(Asdf data)
	{
		if (data.kind() == Asdf.Kind.string)
		{
			string ver = asdf.deserialize!string(data);
			return new DubDependency(ver);
		}
		else
		{
			return deserializeMembers!(DubDependency, false)(data);
		}
	}

	@serializationKeys("version") string version_;
	string path;
	bool optional = false;
	@serializationKeys("default") bool default_ = false;
}

class DubProject
{
	static DubProject deserialize(Asdf data)
	{
		return deserializeMembers!(DubProject, true)(data);
	}

	@serializationIgnore string dubPath;
	@serializationIgnore string rootPackage; // set when this package is a subpackage

	bool isSubPackage()
	{
		return !!rootPackage;
	}

	string fullname(string subPackage)
	{
		if (!subPackage)
		{
			if (rootPackage)
				return rootPackage ~ ":" ~ name;
			else
				return name;
		}
		else if (rootPackage)
			return rootPackage ~ ":" ~ subPackage;
		else
			return name ~ ":" ~ subPackage;
	}

	DubDependency[string] getDependencies(string subPackage, string configuration)
	{
		DubDependency[string] deps = dependencies;
		if (configuration)
		{
			foreach (c; configurations)
			{
				if (c.name == configuration)
				{
					if (c.dependencies)
					{
						/+deps = dependencies.dup;
						//outputln(c.dependencies.byKey);
						foreach (k,v ; c.dependencies)
						{
							if (k in deps)
								errorln(name, ": configuration dependency already in dependencies");
							deps[k] = v;
						}
						//dependencies = c.dependencies;+/
						deps = c.dependencies;
					}
					break;
				}
			}
		}

		if (subPackage)
		{
			assert(subPackages.length > 0, "subpackage specified but none found: " ~ name ~ ":" ~ subPackage);
			deps = null;
			foreach (sub; subPackages)
			{
				if (sub.name == subPackage)
				{
					deps = sub.dependencies;
					break;
				}
			}
		}

		return deps;
	}

	@serializationIgnore static __gshared DubProject[string] allDubProjects;
	static DubProject load(string file)
	{
		file = buildNormalizedPath(file);
		string fullPath = buildNormalizedPath(absolutePath(file));

		DubProject* parsedProject = (fullPath in allDubProjects);
		if (parsedProject)
			return *parsedProject;

		DubProject project;
		try
		{
			if (exists(file))
			{
				string content;
				content = readText(file);
				project = DubProject.deserialize(parseJson(content));
			}
			else if (exists(setExtension(file, ".sdl")))
			{
				string content;
				content = readText(setExtension(file, ".sdl"));
				project = getSdlProject(content);
			}
			else
				return null;//errorln("package not found: ", file);

			project.dubPath = file;
		}
		catch (AsdfException e)
			throw new Exception("failed to parse '" ~ file ~ "': " ~ e.msg);
		catch (Exception e)
			throw new Exception("failed to parse '" ~ file ~ "': " ~ e.msg, e);

		if (!project.validate())
			errorln("failed to validate '" ~ file ~ "'");

		project.defaults();

		allDubProjects[fullPath] = project;

		// preload external subpackages
		foreach (sub; project.subPackages)
		{
			if (sub.path)
			{
				sub.dubPackage = DubProject.load(buildNormalizedPath(dirName(file), sub.path, "dub.json"));
				sub.dubPackage.rootPackage = project.name;
			}
		}

		return project;
	}

	bool validate()
	{
		bool success = validateBuildSettings();
		if (!name)
		{
			outputln("non-optional field name is missing");
			success = false;
		}

		return success;
	}

	void defaults()
	{
		import std.file;
		string rootPath = dirName(dubPath);
		string sourceDir = buildNormalizedPath(rootPath, "source");
		string srcDir = buildNormalizedPath(rootPath, "src");
		string viewDir = buildNormalizedPath(rootPath, "views");

		string[] defaultSourceImportPaths;
		string[] defaultStringImportPaths;
		if (exists(sourceDir) && isDir(sourceDir))
			defaultSourceImportPaths ~= "source";
		else if (exists(srcDir) && isDir(srcDir))
			defaultSourceImportPaths ~= "src";
		if (exists(viewDir) && isDir(viewDir))
			defaultStringImportPaths ~= "views";

		if (!sourcePaths)
			sourcePaths[null] ~= defaultSourceImportPaths;
		if (!importPaths)
			importPaths[null] ~= defaultSourceImportPaths;
		if (!stringImportPaths)
			stringImportPaths[null] = defaultStringImportPaths;

		foreach (subPackage; subPackages)
		{
			if (subPackage.path == null)
			{
				if (!subPackage.sourcePaths)
					subPackage.sourcePaths[null] ~= defaultSourceImportPaths;
				if (!subPackage.importPaths)
					subPackage.importPaths[null] ~= defaultSourceImportPaths;
				if (!subPackage.stringImportPaths)
					subPackage.stringImportPaths[null] = defaultStringImportPaths;

				applyDefaultBuildTypes(subPackage.buildTypes);
			}
		}

		applyDefaultBuildTypes(buildTypes);
	}

	static private void applyDefaultBuildTypes(ref DubBuildType[string] buildTypes)
	{
		buildTypes.require("plain", DubBuildType([]));
		buildTypes.require("debug", DubBuildType([BuildOption.debugMode, BuildOption.debugInfo]));
		buildTypes.require("release", DubBuildType([BuildOption.releaseMode, BuildOption.optimize, BuildOption.inline]));
		buildTypes.require("release-debug", DubBuildType([BuildOption.releaseMode, BuildOption.optimize, BuildOption.inline, BuildOption.debugInfo]));
		buildTypes.require("release-nobounds", DubBuildType([BuildOption.releaseMode, BuildOption.optimize, BuildOption.inline, BuildOption.noBoundsCheck]));
		buildTypes.require("unittest", DubBuildType([BuildOption.unittests, BuildOption.debugMode, BuildOption.debugInfo]));
		buildTypes.require("docs", DubBuildType([BuildOption.syntaxOnly], ["-c", "-Dddocs"]));
		buildTypes.require("ddox", DubBuildType([BuildOption.syntaxOnly], ["-c", "-Df__dummy.html", "-Xfdocs.json"]));
		buildTypes.require("profile", DubBuildType([BuildOption.profile, BuildOption.optimize, BuildOption.inline, BuildOption.debugInfo]));
		buildTypes.require("profile-gc", DubBuildType([BuildOption.profileGC, BuildOption.debugInfo]));
		buildTypes.require("cov", DubBuildType([BuildOption.coverage, BuildOption.debugInfo]));
		buildTypes.require("unittest-cov", DubBuildType([BuildOption.unittests, BuildOption.coverage, BuildOption.debugMode, BuildOption.debugInfo]));
		buildTypes.require("syntax", DubBuildType([ BuildOption.syntaxOnly ]));
	}

	string getDefaultConfiguration(BuildSettings buildSettings, bool ignoreAppLib = false)
	{
		string configuration;
		bool isApp = !ignoreAppLib && isApplication(buildNormalizedPath(dirName(dubPath)), name)/*&& !isDependency*/;

		foreach (cfg; configurations)
		{
			if (cfg.name == "unittest" && !buildSettings.unitTest)
				continue;

			if (cfg.targetType == TargetType.executable && !isApp)
				continue;

			if (cfg.platforms.length > 0)
			{
				foreach (platform; cfg.platforms)
				{
					if (!buildSettings.platformMatches(platform))
						continue;

					configuration = cfg.name;
					break;
				}
			}
			else
				configuration = cfg.name; // no platforms specified is match for all platforms

			if (configuration)
				break;
		}

		if (!configuration && !ignoreAppLib)
		{
			if (isApp)
				configuration = "application";
			else
				configuration = "library";
		}

		return configuration;
	}

	string getSubConfiguration(string packageName, string configuration)
	{
		string depConfiguration = null;
		if (subConfigurations)
			depConfiguration = subConfigurations.get(packageName, null);

		foreach (cfg; configurations)
		{
			if (cfg.name == configuration)
			{
				if (cfg.subConfigurations)
					depConfiguration = cfg.subConfigurations.get(packageName, depConfiguration);
				break;
			}
		}

		return depConfiguration;
	}

	string name;
	string description;
	string[string] toolchainRequirements;
	string homepage;
	string[] authors;
	string copyright;
	string license;
	@serializationKeys("version") string version_;

	@serializationKeysSdl("subPackage") DubSubPackage[] subPackages;
	@serializationKeysSdl("configuration") DubConfiguration[] configurations;
	@serializationKeysSdl("buildType") DubBuildType[string] buildTypes;
	@serializationKeys("-ddoxFilterArgs") string[] ddoxFilterArgs;

	mixin BuildSettingsMixin;
}

mixin template BuildSettingsMixin()
{
	@serializationKeysSdl("dependency") /*@platformProperty*/ DubDependency[string] dependencies; // platform versions seems to alias to this?
	@platformProperty string[string] systemDependencies; // always override the base
	TargetType targetType;
	string targetName;
	string targetPath;
	string workingDirectory;
	@serializationKeysSdl("subConfiguration") string[string] subConfigurations;
	@platformProperty BuildRequirement[][string] buildRequirements;
	@platformProperty BuildOption[][string] buildOptions;
	@platformProperty string[][string] libs;
	@platformProperty string[][string] sourceFiles;	// alias to "string[] files"
	@platformProperty string[][string] sourcePaths; // alias to single "string sourcePath", append
	@platformProperty string[][string] excludedSourceFiles;
	string mainSourceFile;
	@platformProperty string[][string] copyFiles;
	@platformProperty string[][string] versions;
	@platformProperty string[][string] debugVersions;
	@platformProperty string[][string] importPaths;
	@platformProperty string[][string] stringImportPaths;
	@platformProperty string[][string] preGenerateCommands;
	@platformProperty string[][string] postGenerateCommands;
	@platformProperty string[][string] preBuildCommands;
	@platformProperty string[][string] postBuildCommands;
	@platformProperty string[][string] preRunCommands;
	@platformProperty string[][string] postRunCommands;
	@platformProperty string[][string] dflags;
	@platformProperty string[][string] lflags;
//	@platformProperty string[] extraDependencyFiles?
// 	@platformProperty string[] -versionFilters
// 	@platformProperty string[] -debugVersionFilters

	bool validateBuildSettings()
	{
		bool success = true;

		return success;
	}
}

unittest
{
	DubProject jsonProject(string json)
	{
		return DubProject.deserialize(parseJson(json));
	}

	{
		DubProject test = jsonProject(`{"name":"test"}`);
		test.defaults();
		assert("debug" in test.buildTypes);
	}
	{
		DubProject test = jsonProject(`{"name":"test","subPackages":[{"name":"sub"}]}`);
		test.defaults();
		assert(test.subPackages.length == 1);
		assert("debug" in test.subPackages[0].buildTypes);
	}
}

private enum TraverseStrategy
{
	DepthFirst,
	BreadthFirst,
}

alias byDependenciesDepth = byDependenciesImpl!(TraverseStrategy.DepthFirst, false);
alias byDependenciesBreadth = byDependenciesImpl!(TraverseStrategy.BreadthFirst, false);
alias byDependencies = byDependenciesDepth;
alias byPackages = byDependenciesImpl!(TraverseStrategy.DepthFirst, true);

// traverses through package dependencies, skipping already visited packages
struct byDependenciesImpl(TraverseStrategy S, bool includeSelf = false)
{
	bool[string] visitedPackages;

	struct Package
	{
		DubProject pkg;
		string subPackage;
		string configuration;
		int depth;

		alias pkg this;
	}
	Package[] packageStack;
	static if (S == TraverseStrategy.BreadthFirst)
	{
		Package[] packageStackNext;
		int currentDepth;
	}

	this(DubProject pkg, string subPackage, string configuration)
	{
		if (pkg)
		{
			string name = pkg.rootPackage ? (pkg.rootPackage ~ ":" ~ pkg.name) : subPackage ? (pkg.name ~ ":" ~ subPackage) : pkg.name;
			visitedPackages[name] = true;

			Package rootPackage = Package(pkg, subPackage, configuration);
			static if (includeSelf)
				packageStack ~= rootPackage;

			addDependencies(rootPackage);
		}

		static if (S == TraverseStrategy.BreadthFirst && !includeSelf)
			popDepth();
	}

	private void addDependencies(Package pkg)
	{
		foreach (depName, dep; pkg.getDependencies(pkg.subPackage, pkg.configuration))
		{
			if (depName in visitedPackages)
				continue;
			visitedPackages[depName] = true;

			string depSubPackage = dep.dubPackage.rootPackage ? null : getSubPackageName(depName);
			string depConfiguration = pkg.getSubConfiguration(depName, pkg.configuration);

			static if (S == TraverseStrategy.DepthFirst)
				packageStack ~= Package(dep.dubPackage, depSubPackage, depConfiguration, pkg.depth+1);
			else
				packageStackNext ~= Package(dep.dubPackage, depSubPackage, depConfiguration, currentDepth+1);
		}
	}

	static if (S == TraverseStrategy.BreadthFirst)
	{
		private void popDepth()
		{
			currentDepth++;
			packageStack = packageStackNext;
			packageStackNext = null;
		}
	}

	bool empty()
	{
		static if (S == TraverseStrategy.DepthFirst)
			return packageStack.length == 0;
		else
			return packageStack.length == 0 && packageStackNext.length == 0;
	}

	Package front()
	{
		return packageStack[$-1];
	}

	void popFront()
	{
		Package pkg = front();
		packageStack = packageStack[0..$-1];
		addDependencies(pkg);

		static if (S == TraverseStrategy.BreadthFirst)
		{
			if (packageStack.length == 0)
				popDepth();
		}
	}
}

void testIter()//unittest
{
	DubProject stubProject(string name)
	{
		DubProject p = new DubProject();
		p.name = name;
		return p;
	}

	void addDep(DubProject p, DubProject dep)
	{
		auto d = new DubDependency();
		d.dubPackage = dep;
		p.dependencies[dep.name] = d;
	}

	DubProject foo = stubProject("foo");
	DubProject bar = stubProject("bar");
	DubProject baz = stubProject("baz");
	DubProject qux = stubProject("qux");
	DubProject quux = stubProject("quux");
	addDep(foo, bar);
	addDep(foo, baz);
	addDep(bar, qux);
	addDep(qux, quux);

	{
		string[] names;
		foreach (DubProject pkg; foo.byDependenciesDepth(null, null))
			names ~= pkg.name;

		assert(names == ["bar", "qux", "quux", "baz"], names.join(" "));
	}
	{
		string[] names;
		foreach (pkg; foo.byDependenciesBreadth(null, null))
			names ~= pkg.name;

		assert(names == ["bar", "baz", "qux", "quux"], names.join(" "));
	}
}