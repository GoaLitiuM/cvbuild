import std.stdio : writeln;

// DMD with -od produces bar.o for both of these modules
import foo.bar;
import bar;

void main()
{
	if (one && two)
		writeln("ok");
}