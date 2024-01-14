import std.stdio;

import cvbuild.tests.sourcelib;
import cvbuild.tests.dynamiclib;
import cvbuild.tests.staticlib;

void main()
{
	write("sourcelib: ");
	test2();
	write("dynamiclib: ");
	test3();
	write("staticlib: ");
	test4();
}
