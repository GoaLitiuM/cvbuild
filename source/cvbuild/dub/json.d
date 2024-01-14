module cvbuild.dub.json;

import cvbuild.serialization;

import std.traits;
//import std.meta;
import std.meta : aliasSeqOf;

import std.string : indexOf;

import asdf;

TT deserializeMembers(TT, bool handlePlatform)(Asdf data)
{
	static if (is(TT == class))
		TT thing = new TT();
	else
		TT thing;

	nextkey: foreach (key, value; data.byKeyValue)
	{
		static if (handlePlatform)
		{
			const(char)[] platform = null;
			size_t dashind = indexOf(key, '-');
			if (dashind != -1)
			{
				platform = key[dashind+1..$];
				key = key[0..dashind];
			}
		}

		// this switch-case is more performant this way, don't touch it
		switch (key)
		{
			foreach (member; getSerializableMembers!TT)
			{
				enum keys = getSerializationKeys(member, [getUDAs!(__traits(getMember, TT, member), asdf.Serialization)]);
				foreach (keyIn; aliasSeqOf!(keys))
				{
				case keyIn:
				}
					alias T = typeof(__traits(getMember, thing, member));
					static if (handlePlatform && hasUDA!(__traits(getMember, thing, member), platformProperty))
					{
						static assert(__traits(compiles, __traits(getMember, thing, member)[platform]), "member '" ~ member ~ "' with @platformProperty must be an AA[string]");
						alias Tv = ValueType!T;
						Tv val = void;
						asdf.deserializeValue!Tv(value, val);
						__traits(getMember, thing, member)[platform] = val;
					}
					else
						asdf.deserializeValue!T(value, __traits(getMember, thing, member));
					continue nextkey;
			}
			default:
				break;
		}
	}

	return thing;
}
