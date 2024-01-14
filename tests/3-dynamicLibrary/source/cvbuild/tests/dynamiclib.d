module cvbuild.tests.dynamiclib;

import std.stdio;

void test3()
{
	writeln("ok");
}

version (Windows)
{
	// Windows requires dllmain entrypoint
	import core.sys.windows.windows;
	import core.sys.windows.dll;
	mixin SimpleDllMain;
}