module app;

import std.stdio : writeln;
import dmd.frontend;
import dmd.globals;

void main()
{
	//initDMD();
	global._init();
	if (global.vendor)
		writeln("ok");
	else
		writeln("fail, DMD not built with -version=MARS");
}