module cvbuild.dub.sdl;

import cvbuild.serialization;
import cvbuild.dubpackage;

import sdlang.parser;
import sdlang.ast;
import sdlang.token;

import std.traits;
import std.meta : aliasSeqOf;
import asdf;

struct SdlKeys
{
	string[] keys;
}
SdlKeys serializationKeysSdl(string[] keys...) pure @safe
{
	return SdlKeys(keys);
}

string[] getSdlSerializationKeys(string member, SdlKeys[] attrs)
{
	if (attrs.length == 0)
		return [member];
	else
	{
		string[] keys;
		foreach (a; attrs)
			keys ~= a.keys;
		return keys;
	}
}

DubProject getSdlProject(string content)
{
	Tag root = parseSource(content, "dub.sdl");

	DubProject project = new DubProject();

	nextkey: foreach (Tag tag; root.tags)
	{
		string key = tag.name;
		switch (key)
		{
		foreach (member; getSerializableMembers!DubProject)
		{
			//project.name = root.getTagValue!string("name");
			alias T = typeof(__traits(getMember, project, member));

			import cvbuild.globals;
			import std.meta : aliasSeqOf;

			//case member:
			enum keys = getSdlSerializationKeys(member, [getUDAs!(__traits(getMember, DubProject, member), SdlKeys)]);
			enum hasPlatformFlag = hasUDA!(__traits(getMember, DubProject, member), platformProperty);
			foreach (keyIn; aliasSeqOf!(keys))
			{
			//pragma(msg, TT.stringof ~ "." ~ keyIn);
			case keyIn:
			/*if (keyIn != member)
				outputln("parsing ", member, " (", keyIn, ")");
			else
				outputln("parsing ", member);*/
			}

				parseTag(__traits(getMember, project, member), tag, hasPlatformFlag);
				continue nextkey;
		}
		default:
			break;
		}
	}

	return project;
}

T sdlParseClass(T)(ref Tag tag) // SDL tree
if (is(T == class) || is(T == struct))
{
	// TODO: Values[] -> T.init(...)
	T t = void;
	Value[] values = tag.values;
	if (values.length == 1)
	{
		string str = parseValue!string(values[0]);
		static if (is(T == class))
			t = new T(str);//new T();
		else static if (is(T == struct))
			t = T(str);
	}
	else if (values.length == 0)
	{
		static if (is(T == class))
			t = new T();
		else static if (is(T == struct))
			t = T();
	}
	else
		assert(0);

	nextattr: foreach (Attribute attr; tag.attributes)
	{
		switch (attr.name)
		{
			foreach (submember; getSerializableMembers!T)
			{
				//enum subkeys = getSdlSerializationKeys(submember, [getUDAs!(__traits(getMember, Tv, submember), SdlKeys)]);
				enum subkeys = getSerializationKeys(submember, [getUDAs!(__traits(getMember, T, submember), asdf.Serialization)]);
				foreach (subKeyIn; aliasSeqOf!(subkeys))
				{
					//pragma(msg, member.stringof ~":"~ subKeyIn);
				//pragma(msg, TT.stringof ~ "." ~ keyIn);
			case subKeyIn:
				/*if (subKeyIn != submember)
					outputln("subparsing ", submember, " (", subKeyIn, ")");
				else
					outputln("subparsing ", submember);*/
				}
			//case submember:
				//outputln("assigned to ", submember);
				alias Tva = typeof(__traits(getMember, t, submember));
				__traits(getMember, t, submember) = attr.value.get!Tva;
				//parseTag(__traits(getMember, t, submember), subtag);
				continue nextattr;
			}
			default:
				break;
		}
	}

	nexttag: foreach (Tag subtag; tag.tags)
	{
		switch (subtag.name)
		{
			foreach (submember; getSerializableMembers!T)
			{
				import asdf;
				//enum subkeys = getSdlSerializationKeys(submember, [getUDAs!(__traits(getMember, Tv, submember), SdlKeys)]);
				enum subkeys = getSerializationKeys(submember, [getUDAs!(__traits(getMember, T, submember), asdf.Serialization)]);
				enum hasPlatformFlag = hasUDA!(__traits(getMember, T, submember), platformProperty);
				foreach (subKeyIn; aliasSeqOf!(subkeys))
				{
			case subKeyIn:
				/*if (subKeyIn != submember)
					outputln("subparsing ", submember, " (", subKeyIn, ")");
				else
					outputln("subparsing ", submember);*/
				}

				parseTag(__traits(getMember, t, submember), subtag, hasPlatformFlag);
				continue nexttag;
			}
			default:
				break;
		}
	}

	return t;
}

T parseValue(T)(ref Value value)
{
	static if (is(T == enum))
	{
		import std.conv : to;
		string enumStr = value.get!string();
		if (enumStr)
			return to!T(enumStr);
		else
			return T.init;
	}
	else
		return value.get!T();
}

void parseTag(T)(ref T target, ref Tag tag, bool isPlatformFlag)
{
	static if (isArray!T && !isSomeString!T)
	{
		alias TheType(V : V[]) = V;
		alias Tt = TheType!T;

		static if (is(Tt == class) || is(Tt == struct))
			target ~= sdlParseClass!Tt(tag);
		else
		{
			Value[] values = tag.values;
			foreach (v; values)
				target ~= parseValue!Tt(v);//v.get!Tt;
		}
	}
	else static if (isAssociativeArray!T)
	{
		alias Tk = KeyType!T;
		alias Tv = ValueType!T;

		assert(tag.values.length > 0);

		Tk k = void;
		Tv v = void;

		if (isPlatformFlag)
		{
			k = tag.getAttribute!string("platform", null);
			static if (is(Tv == class))
			{
				//pragma(msg, "newing: " ~ Tv.stringof);
				v = sdlParseClass!Tv(tag);//v = new Tv();
			}
			else
				v = Tv.init;

			static if (isArray!Tv && !isSomeString!Tv)
			{
				alias TheType(V : V[]) = V;
				alias Tt = TheType!Tv;
				foreach (val; tag.values)
					v ~= parseValue!Tt(val);//val.get!Tt;
			}
			else
			{
				assert(tag.values.length == 1);
				v = parseValue!Tv(tag.values[0]);//tag.values[0].get!Tv;
			}

		}
		else
		{
			k = parseValue!Tk(tag.values[0]);
			if (tag.values.length > 1)
				v = parseValue!Tv(tag.values[1]);
			else
			{
				static if (is(Tv == class))
				{
					//pragma(msg, "newing: " ~ Tv.stringof);
					v = sdlParseClass!Tv(tag);//v = new Tv();
				}
				else
					v = Tv.init;
			}
		}

		target[k] = v;

		//pragma(msg, "AA: " ~ T.stringof);
	}
	else
		target = parseValue!T(tag.values[0]);
}

unittest
{
	import asdf;
	import cvbuild.globals;
	DubProject jsonProject(string json)
	{
		return DubProject.deserialize(parseJson(json));
	}
	DubProject sdlProject(string sdl)
	{
		return getSdlProject(sdl);
	}

	bool membersEqual(U)(U a, U b)
	{
		foreach (member; getSerializableMembers!U)
		{
			alias T = typeof(__traits(getMember, a, member));
			if (__traits(getMember, a, member) == __traits(getMember, b, member))
				continue;

			return false;
		}
		return true;
	}

	bool isEqual(DubProject a, DubProject b)
	{
		foreach (member; getSerializableMembers!DubProject)
		{
			alias T = typeof(__traits(getMember, a, member));

			import std.traits;

			if (__traits(getMember, a, member) == __traits(getMember, b, member))
				continue;
			else static if (isArray!T && !isSomeString!T)
			{
				if (__traits(getMember, a, member).length == __traits(getMember, b, member).length)
				{
					alias TheType(V : V[]) = V;
					alias Tt = TheType!T;

					bool allOk = true;
					for (size_t i=0; i<__traits(getMember, a, member).length; i++)
					{
						if (__traits(getMember, a, member)[i] == __traits(getMember, b, member)[i])
							continue;
						static if (is(Tt == class))
						{
							if (membersEqual(__traits(getMember, a, member)[i], __traits(getMember, b, member)[i]))
								continue;
						}
						allOk = false;
						break;
					}
					if (allOk)
						continue;
				}
			}
			else static if (isAssociativeArray!T)
			{
				alias Tk = KeyType!T;
				alias Tv = ValueType!T;
				if (__traits(getMember, a, member).length == __traits(getMember, b, member).length)
				{
					bool allOk = true;
					foreach (k; __traits(getMember, a, member).byKey)
					{
						Tv* va = k in __traits(getMember, a, member);
						Tv* vb = k in __traits(getMember, b, member);
						if (!vb)
						{
							allOk = false;
							break;
						}
						if (*va == *vb)
							continue;

						static if (is(Tv == class))
						{
							if (membersEqual(*va, *vb))
								continue;
						}

						allOk = false;
						break;
					}
					if (allOk)
						continue;
				}
			}

			import std.conv;
			assert(0, "member '" ~ member ~ "' differs: " ~ to!string(__traits(getMember, a, member)) ~ " <-> " ~ to!string(__traits(getMember, b, member)));
			return false;
		}

		return true;
	}

	assert(isEqual(jsonProject(`{"name":"test"}`), sdlProject(`name "test"`)));
	assert(isEqual(jsonProject(`{"authors":["foo","bar"]}`), sdlProject(`authors "foo" "bar"`)));
	assert(isEqual(jsonProject(`{"targetType":"staticLibrary"}`), sdlProject(`targetType "staticLibrary"`)));
	assert(isEqual(jsonProject(`{"subConfigurations":{"lib":"libconfig"}}`), sdlProject(`subConfiguration "lib" "libconfig"`)));
	assert(isEqual(jsonProject(`{"dependencies":{"lib":">=1.0.0"}}`), sdlProject(`dependency "lib" version=">=1.0.0"`)));
	assert(isEqual(jsonProject(`{"dependencies":{"lib":">=1.0.0","test:sub":"*"}}`), sdlProject(`dependency "lib" version=">=1.0.0";dependency "test:sub" version="*"`)));

	assert(isEqual(jsonProject(`{"subPackages":["./simple/"]}`), sdlProject(`subPackage "./simple/"`)));
	assert(isEqual(jsonProject(`{"subPackages":[{"name":"complex","targetType":"library"}]}`), sdlProject(`subPackage {` ~ "\n\t" ~ `name "complex"` ~ "\n\t" ~ `targetType "library"` ~ "\n}")));

	assert(isEqual(jsonProject(`{"dflags-windows":["foo","bar"]}`), sdlProject(`dflags "foo" "bar" platform="windows"`)));

	assert(isEqual(jsonProject(`{"buildRequirements":["requireBoundsCheck"]}`), sdlProject(`buildRequirements "requireBoundsCheck"`)));
	assert(isEqual(jsonProject(`{"configurations":[{"name":"test","targetType":"none"}]}`), sdlProject(`configuration "test" {` ~ "\n\t" ~ `targetType "none"` ~ "\n}")));
	assert(isEqual(jsonProject(`{"libs":["foo","bar","baz"]}`), sdlProject(`libs "foo" "bar" "baz"`)));
}