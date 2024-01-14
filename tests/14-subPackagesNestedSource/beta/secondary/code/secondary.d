module secondary;

import std.stdio : writeln;
import sub.secondarysub; // ambiquity here, could be "import secondarysub;" too

void secondaryfun()
{
	writeln("sublibtest2: ok");
	secondarysubfun();
}
