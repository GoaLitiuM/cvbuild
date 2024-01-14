module cvbuild.dub.dependencyresolver;

import cvbuild.buildsettings;
import cvbuild.dubpackage;
import cvbuild.globals;
import cvbuild.helpers;
import cvbuild.semver;

import std.path;

DubProject loadMainPackage(string path, BuildSettings buildSettings)
{
	struct DepVer
	{
		SemVerRange verRange;
		string configuration;
		string branch;
		string path;
		bool loaded = false;
		DubProject project;
		size_t dependants = 0;

		this(SemVerRange verRange, string path)
		{
			this.verRange = verRange;
			this.path = path;
		}

		this(string branch)
		{
			//verMin = verMax = SemVer.max;
			this.branch = branch;
		}

		this(DubDependency dep, string packagePath, string subPackagePath)
		{
			if (dep.path || subPackagePath)
			{
				//verMin = verMax = SemVer.max;

				import std.path;
				//if (dep.path || subPackagePath)
				if (subPackagePath)
					path = buildNormalizedPath(packagePath, subPackagePath, dep.path);
				else
					path = buildNormalizedPath(packagePath, dep.path);
			}
			else if (dep.version_ == "~master")
			{
				//verMin = verMax = SemVer.max; // maybe?
				branch = dep.version_;
			}
			else
			{
				verRange = SemVerRange(dep.version_);
				assert(verRange.isValid());
			}
		}

		string toString()
		{
			if (branch)
				return "~" ~ branch;
			else if (path)
				return "path: " ~ path;
			else
				return verRange.toString();
		}
	}

	DepVer[string] dependencies;

	DubProject getSubPackage(DubProject project, string subPackageName)
	{
		if (!subPackageName)
			return project;
		else if (project.rootPackage && project.name == subPackageName)
			return project;

		foreach (sub; project.subPackages)
		{
			if (sub.name != subPackageName)
				continue;

			if (sub.path)
				return sub.dubPackage;
			return project;
		}
		errorln("package '", project.name, "' does not contain subPackage '", subPackageName, "'");
		return null;
	}

	DubProject mainProject;
	string mainPath = ".";
	if (!buildSettings.dubPackage)
		mainProject = DubProject.load("dub.json");
	else if (buildSettings.dubPackage[0] == ':')
	{
		mainProject = DubProject.load("dub.json");
		if (mainProject)
			mainProject = getSubPackage(mainProject, getSubPackageName(buildSettings.dubPackage));
		else
		{
			// root package does not exist, assume subPackage is under subdirectory with same name
			mainProject = DubProject.load(buildNormalizedPath(buildSettings.dubPackage[1..$], "dub.json"));
		}
		mainPath = buildNormalizedPath(dirName(mainProject.dubPath));
	}
	else
		errorln("building arbitrary dub packages not implemented yet");

	if (!mainProject)
		errorln("could not find package configuration file");

	string mainName = mainProject.rootPackage ? (mainProject.rootPackage ~ ":" ~ mainProject.name) : mainProject.name;//: (mainProject.name ~ (mainSubPackage ? (":" ~ mainSubPackage) : ""));
	dependencies[mainName] = DepVer(SemVerRange("*"), mainPath);
	dependencies[mainName].dependants = 1; // the universe depends on this package
	dependencies[mainName].configuration = buildSettings.configuration;


	import cvbuild.dub.registry;

	string[] registryPackages;
	string[] getRegistryPackages(bool dirty = false)
	{
		if (dirty)
		{}
		else if (registryPackages)
			return registryPackages;

		string[] packages;
		import std.file;
		foreach (DirEntry e; dirEntries(registryPackagesPath, SpanMode.shallow))
			packages ~= baseName(e.name);

		registryPackages = packages;
		return packages;
	}
	//registryPackages = getRegistryPackages(true);

	while (true)
	{
		string[string] packageQueue;

		foreach (dep, ver; dependencies)
		{
			if (ver.loaded || ver.project)
				continue;

			if (ver.path)
			{
				//packageQueue ~= ver.path;
				string verPath = ver.path;
				packageQueue[dep] = verPath;
				dependencies[dep].loaded = true;
				continue;
			}

			// TODO: we should always fetch first, and save the cached results to dub.selection.json

			string rootPackage = getRootPackageName(dep);
			string[] foundVersions = findPackages(getRegistryPackages(), rootPackage);
			string deppath;

			if (ver.branch)
				deppath = choosePackage(foundVersions, ver.branch);
			else if (ver.verRange.min == ver.verRange.max && ver.verRange.min != SemVer.max)
				deppath = choosePackage(foundVersions, ver.verRange.min, "==");
			else
				deppath = choosePackage(foundVersions, ver.verRange.min, ">=", ver.verRange.max, "<");
			if (!deppath)
			{
				import cvbuild.dub.command;
				outputln("package: ", dep, " not found for version range '", ver.verRange.toString(), "', fetching...");

				string fetchPackage;
				if (ver.branch)
					fetchPackage = rootPackage ~ "=" ~ ver.branch;
				else
					fetchPackage = rootPackage ~ `=` ~ ver.verRange.toString();

				DubResult result = dubRun(["fetch", fetchPackage]);
 				if (result.returnCode != 0)
					errorln("failed to fetch dub package, dub fetch:\n", result.output);

				foundVersions = findPackages(getRegistryPackages(true), rootPackage);
				if (ver.branch)
					deppath = choosePackage(foundVersions, ver.branch);
				else if (ver.verRange.min == ver.verRange.max && ver.verRange.min != SemVer.max)
					deppath = choosePackage(foundVersions, ver.verRange.min, "==");
				else
					deppath = choosePackage(foundVersions, ver.verRange.min, ">=", ver.verRange.max, "<");
				if (!deppath)
					errorln("failed to choose package '", dep, " ", ver.branch ? ver.branch : ver.verRange.toString(), "'");
			}
			string packagePath = buildPath(registryPackagesPath, rootPackage ~ "-" ~ deppath, rootPackage);
			packageQueue[dep] = packagePath;
			dependencies[dep].loaded = true;
		}

		// discover packages
		foreach (pkgDep, pkg; packageQueue)
		{
			import std.path;
			DubProject project = DubProject.load(buildNormalizedPath(pkg, "dub.json"));
			DubProject rootProject = project;
			assert(project, "failed to load project '" ~ pkg ~ "' (" ~ buildNormalizedPath(absolutePath(pkg)) ~ ")");

			string rootSubPackageName = getSubPackageName(pkgDep);
			project = getSubPackage(project, rootSubPackageName);


			dependencies[pkgDep].project = project;
			string configuration = dependencies[pkgDep].configuration;
			if (!configuration)
			{
				if (rootSubPackageName)
					configuration = rootProject.getSubConfiguration(rootSubPackageName, rootProject.getDefaultConfiguration(buildSettings));
				else
					configuration = project.getDefaultConfiguration(buildSettings);
			}
			string rootPackage = rootProject.name;

			if (printDependencyResolve)
				outputln("discovered ", pkgDep);

			DubDependency[string][] allDeps;
			allDeps ~= project.getDependencies(project.rootPackage ? null : rootSubPackageName, configuration);

			foreach (deps; allDeps)
			foreach (depName, dep; deps)
			{
				import std.string;
				string packageName = getRootPackageName(depName);
				string subPackageName = getSubPackageName(depName);
				string subPackagePath = null;

				string depConfiguration;
				if (subPackageName && rootPackage == packageName)
				{
					depConfiguration = rootProject.getSubConfiguration(subPackageName, configuration);

					foreach (sub; rootProject.subPackages)
					{
						if (sub.name == subPackageName)
						{
							if (sub.path)
							{
								subPackagePath = sub.path;
								packageName = depName; // external subpackage
							}
							else
								subPackagePath = ".";
							break;
						}
					}
				}

				DepVer nv = DepVer(dep, pkg, subPackagePath);
				nv.configuration = depConfiguration;
				if (subPackagePath == ".")
					nv.project = project;

				if (rootProject.name == packageName)
				{
					// we depend on a sister package
					auto ov = dependencies[pkgDep];
					auto oldProject = nv.project;
					nv = ov;
					//nv.project = oldProject;
					nv.project = null;
					nv.loaded = false;
				}

				if (depName in dependencies)
				{
					auto ov = dependencies[depName];

					if (nv.verRange.min == ov.verRange.min && nv.verRange.max == ov.verRange.max && nv.path == ov.path && nv.branch == ov.branch && nv.configuration == ov.configuration)
					{
						ov = ov;
						continue;
					}
					else
					{
						if (printDependencyResolve)
							outputln(pkgDep, " depends on existing dependency: '", depName, "' with new requirements: ", nv.toString());
						if (!nv.path && ov.path)
							errorln("path differs for dep ", depName, ": new: ", nv.path, "  old: ", ov.path);//continue; // FIXME: is this right?
						else if (nv.configuration != ov.configuration)
							errorln("configuration differs for dep ", pkgDep);
						else if (nv.branch == ov.branch)
						{
							SemVerRange newRange = nv.verRange.narrow(ov.verRange);
							if (!newRange.isValid() && !nv.path)
							{
								errorln("unresolvable dependency ", depName, " has no common range within ranges '", nv.verRange.toString(), "' and '", ov.verRange.toString(), "' in ", pkg);
							}
							nv.verRange = newRange;
							//assert(nv.verRange.isValid());
						}
						else
							errorln("replaced ", depName, " version");
					}
				}
				else if (printDependencyResolve)
					outputln(pkgDep, " depends on: '", depName, "' ", nv.toString());

				dependencies[depName] = nv;
			}
		}

		if (packageQueue.length == 0)
			break;
	}

	foreach (pkgName, pkgVer; dependencies)
	{
		//outputln(pkgName);

		string subPackageName = getSubPackageName(pkgName);

		DubDependency[string][] allDeps;
		allDeps ~= pkgVer.project.getDependencies(pkgVer.project.rootPackage ? null : subPackageName, pkgVer.configuration);//pkgVer.project.getDependencies(subPackageName, pkgVer.configuration);

		foreach (deps; allDeps)
		foreach (depName, dep; deps)
		{
			string rootPackage = getRootPackageName(depName);
			dep.subPackage = getSubPackageName(depName);

			DepVer* referedDep = depName in dependencies;
			if (referedDep)
				dep.dubPackage = getSubPackage(referedDep.project, dep.subPackage);//;
			else
			{
				referedDep = rootPackage in dependencies;
				if (referedDep)
					dep.dubPackage = getSubPackage(referedDep.project, dep.subPackage);
				else
					assert(0, "no discovered dependencies of " ~ rootPackage ~ " or " ~ rootPackage ~ ":* were found");
			}
			referedDep.dependants += 1;
		}
	}

	// TODO: remove optionally included dependencies if nobody depends on them

	foreach (pkgName, pkgVer; dependencies)
	{
		assert(pkgVer.project);
		assert(pkgVer.project.dubPath);
		//assert(pkgVer.dependants > 0, "nobody depends on " ~ pkgName);
		if (pkgVer.dependants == 0)
			outputln("found package with no dependants: ", pkgName);


		string subPackageName = getSubPackageName(pkgName);

		DubDependency[string][] allDeps;
		allDeps ~= pkgVer.project.getDependencies(pkgVer.project.rootPackage ? null : subPackageName, pkgVer.configuration);//allDeps ~= pkgVer.project.getDependencies(subPackageName, pkgVer.configuration);

		foreach (deps; allDeps)
		foreach (depName, dep; deps)
		{
			assert(dep.dubPackage);
			assert(dep.dubPackage.dubPath);
		}
	}

	assert(mainProject == dependencies[mainName].project);

	//return dependencies[mainName].project;
	return mainProject;
}