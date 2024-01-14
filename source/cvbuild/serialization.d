module cvbuild.serialization;

import asdf;

import std.meta;
import std.traits;
import std.algorithm.searching: canFind, find, startsWith, count;
import std.functional : unaryFun;
import std.range;

/*private*/ string[] getSerializationKeys(string member, Serialization[] attrs)
{
	alias pred = unaryFun!(a => a.args[0] == "keys" || a.args[0] == "keys-in");
	auto c = attrs.count!pred;
	if(c == 0)
		return [member];
	else if(c == 1)
		return attrs.find!pred.front.args[1 .. $];
	else
		assert(0);
}

/*private*/ template getSerializableMembers(alias T)
{
	enum isNotDisabled(alias memberName) = __traits(getProtection, __traits(getMember, T, memberName)) == "public";
	enum isPublic(alias memberName) = __traits(getProtection, __traits(getMember, T, memberName)) == "public";
	enum hasOffset(alias memberName) = __traits(compiles, __traits(getMember, T, memberName).offsetof);
	enum isIgnored(asdf.Serialization[] s) = s.canFind!(a => a.args == ["ignore"] || a.args == ["ignore-out"]);
	enum notIgnored(alias memberName) = !isIgnored!([getUDAs!(__traits(getMember, T, memberName), asdf.Serialization)]);

	alias getSerializableMembers = Filter!(notIgnored, Filter!(hasOffset, Filter!(isPublic, __traits(allMembers, T))));
}

struct platformProperty { }

private template getPlatformMembers(alias T)
{
	enum hasPlatformProperty(alias memberName) = hasUDA!(__traits(getMember, T, memberName), platformProperty);
	alias getPlatformMembers = Filter!(hasPlatformProperty, getSerializableMembers!T);
}

private template getPlatformFlagRetType(T, alias memberName)
{
	import std.traits;
	alias Type = typeof(__traits(getMember, T, memberName));
	static if (isAssociativeArray!Type)
		alias getPlatformFlagRetType = ValueType!Type;
	else
		alias getPlatformFlagRetType = Type;
}

import cvbuild.dubpackage;
import cvbuild.buildsettings;
T getPlatformFlags(string memberName, T = getPlatformFlagRetType!(DubProject, memberName))(DubProject project, BuildSettings buildSettings, string configuration, string subPackageName, bool inheritBase = false)
{
	string[] keyCombinations = buildSettings.getPlatformCombinations();

	DubSubPackage subPackage;
	if (subPackageName)
	{
		foreach (sub; project.subPackages)
		{
			if (sub.name == subPackageName)
			{
				subPackage = sub;
				break;
			}
		}
	}

	alias Tu = typeof(__traits(getMember, project, memberName));
	static if (isAssociativeArray!Tu)
	{
		T values;

		if (!subPackageName || inheritBase)
		{
			if (__traits(getMember, project, memberName) != null)
			{
				//values ~= __traits(getMember, project, memberName)[null];
				foreach (s; keyCombinations)
				{
					T* v = s in __traits(getMember, project, memberName);
					if (v)
					{
						//outputln("values in ", s, ": ", s.length);
						values ~= *v;
					}
				}
			}

			if (configuration)
			{
				foreach (DubConfiguration c; project.configurations)
				{
					if (c.name == configuration)
					{
						//values ~= __traits(getMember, c, memberName)[null];
						foreach (s; keyCombinations)
						{
							T* v = s in __traits(getMember, c, memberName);
							if (v)
								values ~= *v;
						}
					}
				}
			}

			DubBuildType* buildType = buildSettings.buildType in project.buildTypes;
			if (buildType)
			{
				if (__traits(getMember, *buildType, memberName) != null)
				{
					//values ~= __traits(getMember, *buildType, memberName)[null];
					foreach (s; keyCombinations)
					{
						T* v = s in __traits(getMember, *buildType, memberName);
						if (v)
							values ~= *v;
					}
				}
			}
		}
		if (subPackage)
		{
			if (__traits(getMember, subPackage, memberName) != null)
			{
				//values ~= __traits(getMember, project, memberName)[null];
				foreach (s; keyCombinations)
				{
					T* v = s in __traits(getMember, subPackage, memberName);
					if (v)
					{
						//outputln("values in ", s, ": ", s.length);
						values ~= *v;
					}
				}
			}

			if (configuration)
			{
				foreach (DubConfiguration c; subPackage.configurations)
				{
					if (c.name == configuration)
					{
						//values ~= __traits(getMember, c, memberName)[null];
						foreach (s; keyCombinations)
						{
							T* v = s in __traits(getMember, c, memberName);
							if (v)
								values ~= *v;
						}
					}
				}
			}

			DubBuildType* buildType = buildSettings.buildType in subPackage.buildTypes;
			if (buildType)
			{
				if (__traits(getMember, *buildType, memberName) != null)
				{
					//values ~= __traits(getMember, *buildType, memberName)[null];
					foreach (s; keyCombinations)
					{
						T* v = s in __traits(getMember, *buildType, memberName);
						if (v)
							values ~= *v;
					}
				}
			}
		}

		return values;
	}
	else
	{
		T value;

		if (!subPackageName || inheritBase)
		{
			value = __traits(getMember, project, memberName);

			// TODO: null check before overriding?

			if (configuration)
			{
				foreach (DubConfiguration c; project.configurations)
				{
					if (c.name == configuration)
					{
						value = __traits(getMember, c, memberName);
						break;
					}
				}
			}

			//DubBuildType* buildType = buildSettings.buildType in project.buildTypes;
			//if (buildType)
			//	value = __traits(getMember, *buildType, memberName);
		}

		if (subPackage)
		{
			value = __traits(getMember, subPackage, memberName);

			if (configuration)
			{
				foreach (DubConfiguration c; subPackage.configurations)
				{
					if (c.name == configuration)
					{
						value = __traits(getMember, c, memberName);
						break;
					}
				}
			}

			//DubBuildType* buildType = buildSettings.buildType in project.buildTypes;
			//if (buildType)
			//	value = __traits(getMember, *buildType, memberName);
		}

		return value;
	}
}