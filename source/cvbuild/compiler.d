module cvbuild.compiler;

import cvbuild.dubpackage : BuildOption;

enum CompilerType
{
	DMD,
	LDC2,
	GDC
}

abstract class Compiler
{
	string path;
	CompilerType type;

	// maps BuildOptions to dflags
	abstract @property string[][BuildOption] options();

	// maps DMD-like dflags to compiler specific dflags
	abstract @property string[string] switches();
}

class DmdCompiler : Compiler
{
	__gshared static string[][BuildOption] dmdOptions;
	__gshared static string[string] dmdSwitches;

	this(string path = "dmd")
	{
		this.path = path;
		this.type = CompilerType.DMD;
	}

	override @property string[][BuildOption] options() { return dmdOptions; };
	override @property string[string] switches() { return dmdSwitches; };
}

class LdcCompiler : Compiler
{
	__gshared static string[][BuildOption] ldcOptions;
	__gshared static string[string] ldcSwitches;

	this(string path = "ldc2")
	{
		this.path = path;
		this.type = CompilerType.LDC2;
	}

	override @property string[][BuildOption] options() { return ldcOptions; };
	override @property string[string] switches() { return ldcSwitches; };
}

shared static this()
{
	DmdCompiler.dmdSwitches =
	[
		"-c": "-c",
		"-allinst": "-allinst",
		"-version": "-version",
		"-debug": "-debug",
		"-J": "-J",
		"-lib": "-lib",
		"-shared": "-shared",
		"-od": "-od",
		"-op": "-op",
		"-oq": "",
	];
    DmdCompiler.dmdOptions =
    [
        BuildOption.debugMode: ["-debug"],
        BuildOption.releaseMode: ["-release"],
        BuildOption.debugInfo: ["-g"],
        BuildOption.debugInfoC: ["-g"],
        BuildOption.alwaysStackFrame: ["-gs"],
        BuildOption.stackStomping: ["-gx"],
        BuildOption.inline: ["-inline"],
        BuildOption.noBoundsCheck: ["-noboundscheck"],
        BuildOption.optimize: ["-O"],
        BuildOption.unittests: ["-unittest"],
        BuildOption.profile: ["-profile"],
    ];

	LdcCompiler.ldcSwitches =
	[
		"-c": "-c",
		"-allinst": "-allinst",
		"-version": "-d-version",
		"-debug": "-d-debug",
		"-J": "-J",
		"-lib": "-lib",
		"-shared": "-shared",
		"-od": "-od",
		"-op": "-op",
		"-oq": "-oq",
	];
    LdcCompiler.ldcOptions =
    [
        BuildOption.debugMode: ["-d-debug"],
        BuildOption.releaseMode: ["-release"],
        BuildOption.debugInfo: ["-g"],
        BuildOption.debugInfoC: ["-gc"],
        BuildOption.alwaysStackFrame: [],
        BuildOption.stackStomping: [],
        BuildOption.inline: ["-enable-inlining", "-Hkeep-all-bodies"],
        BuildOption.noBoundsCheck: ["-boundscheck=off"],
        BuildOption.optimize: ["-O3"],
        BuildOption.unittests: ["-unittest"],
        BuildOption.profile: [],
    ];
}