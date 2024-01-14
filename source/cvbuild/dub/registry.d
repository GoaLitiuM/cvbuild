module cvbuild.dub.registry;

import cvbuild.semver;
import cvbuild.globals;

import std.file;
import std.path;
import std.algorithm;

__gshared string registryPackagesPath;

static this()
{
	import std.process : environment;
	version (Windows)
	{
		registryPackagesPath = buildPath(environment.get("LOCALAPPDATA", environment.get("APPDATA")), "dub", "packages");
	}
	else version(Posix)
	{
		registryPackagesPath = buildPath(environment.get("HOME"), ".dub", "packages");
	}
	else
		static assert(0, "dub registry path location not implemented for this platform");
}

string getPackageFromCache(string cacheLocation, string packageName, string versionSpecifier)
{
	string[] registryPackages;
	if (registryPackages == null)
	{
		foreach (DirEntry e; dirEntries(registryPackagesPath, SpanMode.shallow))
			registryPackages ~= baseName(e.name);
	}

	string[] foundVersions = findPackages(registryPackages, packageName);

	string packageVer = choosePackage(foundVersions, versionSpecifier);
	if (!packageVer)
		return null;//errorln("no cached package '", packageName, "'found with version specifier ", versionSpecifier);

	string packagePath = buildPath(registryPackagesPath, packageName ~ "-" ~ packageVer);
	if (!exists(packagePath))
		errorln("no cached package '", packageName, "'found with version specifier ", versionSpecifier);

	//outputln("found cached package: ", buildPath(packagePath, packageName, "dub.json"));
	return buildPath(packagePath, packageName, "dub.json");
}

string[] findPackages(string[] packages, string packageName)
{
	string[] foundPackages;
	foreach (pkg; packages)
	{
		import std.ascii;
		if (!pkg.startsWith(packageName))
			continue;
		else if (pkg == packageName)
		{
			foundPackages ~= ""; // versionless package, not sure how to deal with these
			continue;
		}
		//else if (pkg[packageName.length] != '-')
		//	continue; // package which happens to start with the same name

		//outputln(pkg);
		string ver = pkg[packageName.length+1..$];
		if (ver == "master")
		{
			foundPackages ~= ver;
			continue;
		}
		else if (!isDigit(ver[0]))
			continue; // package which happens to start with the same name

		//if (ver.indexOf("-") != -1)
		//	ver = ver;


		//SemVer sver = SemVer(ver);
		//assert(ver.indexOf("-") == -1, ver);
		foundPackages ~= ver;//sver.toString();
	}
	return foundPackages;
}


unittest
{
	string[] t1 = findPackages(["vibe-core-1.7.0", "vibe-d-0.8.4", "workspace-d-3.4.0", "vibe-d-0.8.6"], "vibe-d");
	assert(t1 == ["0.8.4", "0.8.6"]);

	string[] t2 = findPackages(["painlesstraits-master", "painlesstraits-0.3.0", "painlessjson-master"], "painlesstraits");
	assert(t2 == ["master", "0.3.0"]);

	string[] t3 = findPackages(["vibe-d-0.6.6", "vibe-d-0.6.666", "vibe-d-0.7.9", "vibe-d-0.8.0", "vibe-d-0.8.4", "vibe-d-0.8.6", "vibe-d-0.9.0", "vibe-d-0.10.1"/*, "vibe-d-master"*/], "vibe-d");
	assert(choosePackage(t3, "~>0.7.9") == "0.7.9");
	assert(choosePackage(t3, "~>0.8.4") == "0.8.6");
	assert(choosePackage(t3, "~>0.8") == "0.10.1");

	assert(choosePackage(t3, "==0.8.4") == "0.8.4");
	assert(choosePackage(t3, "==0.6.6") == "0.6.6");
	assert(choosePackage(t3, "0.6.6") == "0.6.6");
	assert(choosePackage(t3, ">=0.8.4") == "0.10.1"); // or master?

	assert(choosePackage(t3, "*") == "0.10.1");
	assert(choosePackage(t3, ">=0.0.0") == "0.10.1");

	assert(choosePackage(t3, ">=0.8.0 <=0.8.5") == "0.8.4");

	string[] t4 = findPackages(["vibe-d-0.8.0", "vibe-d-0.8.4", "vibe-d-0.8.6"], "vibe-d");
	assert(choosePackage(t4, ">0.8.6") == null);
	assert(choosePackage(t4, ">0.8.4") == "0.8.6");

	assert(choosePackage(findPackages(["emsi_containers-0.8.0-alpha.15"], "emsi_containers"), "~>0.8.0-alpha.15") == "0.8.0-alpha.15");
}