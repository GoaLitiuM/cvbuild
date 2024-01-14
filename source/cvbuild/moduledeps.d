module cvbuild.moduledeps;

import cvbuild.buildsettings;
import cvbuild.globals;

import asdf;

import std.path : buildPath, dirName, extension;
import std.array : Appender;
import std.conv : to;
import std.string : toStringz;
import std.file;
import dmd.frontend;
import dmd.transitivevisitor;
//import dmd.frontend : DiagnosticReporter;
import dmd.parse : Parser;
import dmd.astbase : ASTBase;
import dmd.globals : global;
import dmd.identifier : Identifier;

extern(C++) class ImportVisitor(AST) : ParseTimeTransitiveVisitor!AST
{
	string[] imports;
	alias visit = ParseTimeTransitiveVisitor!AST.visit;

	override void visit(AST.Import imp)
	{
		Appender!string str;
		if (imp.packages && imp.packages.dim)
			foreach (const pid; *imp.packages)
			{
				str ~= pid.toString();
				str ~= ".";
			}

		str ~= imp.id.toString();
		imports ~= str.data;
	}
}

class ModuleDep
{
	string[] imports;
	ModuleFile[] dependants;
	bool parsed;
}

struct ModuleDepCache
{
	string[] imports;
	string[] dependants;
}

struct ModuleDepHolder
{
	ModuleDepCache[string] moduleDeps;
	//string[] imports;
	//string[] dependants;
}

ModuleDep[ModuleFile] loadDeps(string file, ModuleFile[] moduleFiles)
{
	if (!exists(file))
		return null;

	// TODO: detect if this cache is valid? (missing/changed files)

	ModuleDepHolder cache;
	cache = readText(file).deserialize!ModuleDepHolder;

	ModuleDep[ModuleFile] moduleDeps;
	ModuleFile[string] pathMap;
	if (cache.moduleDeps.length > 0)
	{
		foreach (ModuleFile moduleFile; moduleFiles)
		{
			ModuleDep mod = moduleDeps.require(moduleFile, new ModuleDep);
			pathMap.require(moduleFile.path, moduleFile);
			//mod.imports = cache.moduleDeps[moduleFile.path].imports;
			//auto c = cache.moduleDeps[moduleFile.path];
			//deps[moduleFile] =
		}

		foreach (k, v; moduleDeps)
		{
			ModuleDepCache* c = k.path in cache.moduleDeps;
			if (!c)
				continue; // file got deleted?
			v.imports = c.imports;
			/*foreach (imp; v.imports)
			{
				imp.dependants ~= moduleFile;
			}*/

			foreach (d; c.dependants)
			{
				ModuleFile* mod = d in pathMap;
				if (!mod)
				{
					if (printDebug)
						outputln("dependency cache is dirty: ", d, " is not in pathMap!");
					else
						outputln("dependency cache is dirty");
					return null;
				}
				v.dependants ~= *mod;
			}
		}
	}
	return moduleDeps;
}
void saveDeps(string file, ref ModuleDep[ModuleFile] moduleDeps)
{
	/*scope*/ ModuleDepHolder cache;// = new ModuleDepHolder();
	foreach (k, v; moduleDeps)
	{
		ModuleDepCache c;
		c.imports = v.imports;
		foreach (d; v.dependants)
			c.dependants ~= d.path;
		cache.moduleDeps[k.path] = c;
	}
	return write(file, serializeToJson(cache));
}




void ResolveDependencies(ModuleFile[] moduleFiles, BuildSettings buildSettings, ref ModuleDep[ModuleFile] moduleDeps)
{
	if (moduleFiles.length == 0)
		return;

	size_t numImports = 0;
	bool parseDirtyOnly = true;
	string depCacheFile = buildPath(buildSettings.buildTarget, "cvbuild_deps.json");

	if (!moduleDeps)
	{
		moduleDeps = loadDeps(depCacheFile, moduleFiles);
		if (!moduleDeps)
			parseDirtyOnly = false;
		else
			return;
	}

	// TODO: use versions from parsed dub projects OR modify ImportVisitor to parse all version blocks
	global.params.useUnitTests = true;
	global.params.is64bit = buildSettings.arch == "x86_64";
	global.params.errorLimit = 0; // workaround for compiler calling exit when too many errors occured

	import dmd.console : Color;
	import dmd.globals : Loc;
	import core.stdc.stdarg : va_list;
	bool diagnosticHandler(const ref Loc location, Color headerColor, const(char)* header, const(char)* messageFormat, va_list args, const(char)* prefix1, const(char)* prefix2)
	{
		return true;
	}

	initDMD(&diagnosticHandler);
	ASTBase.Type._init();

	// TODO: mimic global.vendor based on buildSettings compiler?
	assert(global.vendor); // DMD not built with -version=MARS

	ModuleFile[string] moduleMap;

	/*class NoopDiagnosticReporter : DiagnosticReporter
	{
		import core.stdc.stdarg : va_list;
		import dmd.globals : Loc;

		override int errorCount() { return 0; }
		override int warningCount() { return 0; }
		override int deprecationCount() { return 0; }
		override bool error(const ref Loc loc, const(char)* format, va_list, const(char)* p1, const(char)* p2) { return true; }
		override bool errorSupplemental(const ref Loc loc, const(char)* format, va_list, const(char)* p1, const(char)* p2) { return true; }
		override bool warning(const ref Loc loc, const(char)* format, va_list, const(char)* p1, const(char)* p2) { return true; }
		override bool warningSupplemental(const ref Loc loc, const(char)* format, va_list, const(char)* p1, const(char)* p2) { return true; }
		override bool deprecation(const ref Loc loc, const(char)* format, va_list, const(char)* p1, const(char)* p2) { return true; }
		override bool deprecationSupplemental(const ref Loc loc, const(char)* format, va_list, const(char)* p1, const(char)* p2) { return true; }
	}*/



	//scope diagnosticReporter = new NoopDiagnosticReporter();


	foreach (ModuleFile moduleFile; moduleFiles)
	{
		if (extension(moduleFile.path) != ".d" && extension(moduleFile.path) != ".di" && extension(moduleFile.path) != ".dpp")
			continue;

		if (parseDirtyOnly && !moduleFile.dirty)
			continue;

		ModuleDep mod = moduleDeps.require(moduleFile, new ModuleDep);
		if (!parseDirtyOnly && mod.parsed)
			continue;

		string sourceFile = moduleFile.fullpath;

		string moduleName;
		scope ImportVisitor!ASTBase vis = new ImportVisitor!ASTBase();
		scope Parser!ASTBase p;
		try
		{
			auto id = Identifier.idPool(sourceFile);
			ASTBase.Module m = new ASTBase.Module(sourceFile.toStringz(), id, false, false);

			string input = readText(sourceFile) ~ "\0"; // lexer seems to expect null terminated strings

			p = new Parser!ASTBase(m, input, false);
			p.nextToken();
			m.members = p.parseModule();
			//writeln("Finished parsing. Starting transitive visitor");

			m.accept(vis);
		}
		catch (Throwable t) // annoying workaround to catch asserts due to bad module files
		{
			warningln("failed to parse '", sourceFile, "': ", t.toString());
		}
		if (p && p.md)
			moduleName = to!string(p.md.toChars());
		if (!moduleName)
			moduleName = moduleFile.name;
		assert(moduleName);
		moduleMap.require(moduleName, moduleFile);

		mod.imports = vis.imports;
		mod.parsed = true;
		numImports += mod.imports.length;
	}

	deinitializeDMD();

	foreach (moduleName, moduleFile; moduleMap)
	{
		ModuleDep mod = moduleDeps[moduleFile];
		foreach (importName; mod.imports)
		{
			ModuleFile* impFile = importName in moduleMap;
			if (!impFile)
				continue;
			ModuleDep imp = moduleDeps[*impFile];
			if (!imp)
				continue;

			imp.dependants ~= moduleFile;
		}
	}

	saveDeps(depCacheFile, moduleDeps);
	//GC.minimize();
}