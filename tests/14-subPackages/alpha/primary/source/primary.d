module primary;

import std.stdio;

import primaryone;
import primarytwo;

enum primaryEnum = 1;

void primaryfun()
{
	writeln("primary: ok");
	primaryonefun();
	primarytwofun();
}
