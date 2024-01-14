module app;

import std.stdio;
import testlib;

void main()
{
	version (main_dflag)
		writeln("ok, dflags");
	else
		writeln("fail, missing dflags");

	version (buildtype_dflag)
		writeln("ok, buildtype dflags");
	else
		writeln("fail, missing buildtype dflags");

	version (config_dflag)
		writeln("ok, configuration dflags");
	else
		writeln("fail, missing configuration dflags");

	version (wrong_dflag)
		writeln("fail, wrong configuration dflags");


	version (main_version)
		writeln("ok, versions");
	else
		writeln("fail, missing versions");

	version (buildtype_version)
		writeln("ok, buildtype versions");
	else
		writeln("fail, missing buildtype versions");

	version (config_version)
		writeln("ok, configuration versions");
	else
		writeln("fail, missing configuration versions");

	version (wrong_version)
		writeln("fail, wrong configuration versions");

	version (dep_version)
		writeln("ok, dependency version propagating to parent");
	else
		writeln("fail, dependency version not propagating to parent");

	test();
}
