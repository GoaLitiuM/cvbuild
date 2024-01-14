import std.stdio;

void main()
{
	version (test_feature_a) writeln("test_feature_a");
	version (test_feature_b) writeln("test_feature_b");
	version (5) writeln("version 5");
	version (6) writeln("version 6");
	version (7) writeln("version 7");
	debug (test_debug_a) writeln("test_debug_a");
	debug (test_debug_b) writeln("test_debug_b");
	debug (7) writeln("debug 7");
	debug (8) writeln("debug 8");
	debug (9) writeln("debug 9");
}