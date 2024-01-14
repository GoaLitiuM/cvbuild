module app;

import sub1;
import sub2;

import std.stdio : writeln;
import unit_threaded.assertions;

void main()
{
	// we should never get this far
	static if (is(typeof(isApproxEqual)))
		writeln("fail, unit-threaded:assertions <= 0.8.0");
	else
		writeln("fail, unit-threaded:assertions > 0.8.0");
}