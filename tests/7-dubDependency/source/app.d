module app;

import std.stdio;
import dubnull;

int main()
{
	if (dummy() == "dummy")
		writeln("ok");
	else
		return 1;
	return 0;
}