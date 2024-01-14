module testlib;

import std.stdio;

void subtest()
{
	version (version_default) writeln("fail, default configuration");
	else version (version_wrong) writeln("fail, wrong configuration");
	else version (version_right) writeln("ok");
	else writeln("fail, no configuration");
}

void test()
{
	version (version_main) subtest();
	else writeln("fail, configurations overwrite 'versions'");
}
