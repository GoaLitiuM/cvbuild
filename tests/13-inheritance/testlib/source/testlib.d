module testlib;

import std.stdio;

void test()
{
	version (dep_version)
		writeln("ok, dependency version");
	else
		writeln("fail, dependency version missing");

	version (main_dflag)
		writeln("ok, dflags propagating");
	else
		writeln("fail, dflags not propagating");

	version (buildtype_dflag)
		writeln("ok, buildtype dflags propagating");
	else
		writeln("fail, buildtype dflags not propagating");

	version (config_dflag)
		writeln("ok, configuration dflags propagating");
	else
		writeln("fail, configuration dflags not propagating");


	version (main_version)
		writeln("ok, versions propagating");
	else
		writeln("fail, versions not propagating");

	version (buildtype_version)
		writeln("ok, buildtype versions propagating");
	else
		writeln("fail, buildtype versions not propagating");

	version (config_version)
		writeln("ok, configuration versions propagating");
	else
		writeln("fail, configuration versions not propagating");
}
