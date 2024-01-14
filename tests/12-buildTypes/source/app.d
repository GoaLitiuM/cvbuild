import std.stdio;

void main()
{
	version (feature_version) writeln("feature_version");
	version (buildtype_feature_version) writeln("buildtype_feature_version");

	debug writeln("debugMode");
	else writeln("releaseMode");
}
