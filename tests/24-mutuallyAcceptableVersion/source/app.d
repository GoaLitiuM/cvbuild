module app;

import sub1;
import sub2;

import std.stdio : writeln;
import unit_threaded.assertions;

void main()
{
	isApproxEqual(1.0, 1.0);
	writeln("ok");
}