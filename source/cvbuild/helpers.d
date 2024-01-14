module cvbuild.helpers;

import cvbuild.globals;

import std.file;
import std.stdio;
import std.string : indexOf;
import std.algorithm : filter;
import std.path;
import std.algorithm;
import std.array;
import std.string;

// returns null instead of "." for paths
string trimDot(string path)
{
	if (path == ".")
		return null;
	return path;
}

string getRootPackageName(string packageName)
{
	size_t colonInd = packageName.indexOf(":");
	if (colonInd != -1)
		return packageName[0..colonInd];
	return packageName;
}

string getSubPackageName(string packageName)
{
	size_t colonInd = packageName.indexOf(":");
	if (colonInd != -1)
		return packageName[colonInd+1..$];
	return null;
}

bool isApplication(string path, string packageName)
{
	if (exists(buildNormalizedPath(path, "source", "app.d")) ||
		exists(buildNormalizedPath(path, "source", "main.d")) ||
		exists(buildNormalizedPath(path, "source", packageName, "app.d")) ||
		exists(buildNormalizedPath(path, "source", packageName, "main.d")) ||
		exists(buildNormalizedPath(path, "src", "app.d")) ||
		exists(buildNormalizedPath(path, "src", "main.d")) ||
		exists(buildNormalizedPath(path, "src", packageName, "app.d")) ||
		exists(buildNormalizedPath(path, "src", packageName, "main.d")))
	{
		return true;
	}
	return false;
}

string[] getCombinations(string[] as, string[] bs, string[] cs)
{
	string[] combs;

	foreach (c; cs)
	{
		foreach (b; bs)
		{
			foreach (a; as)
			{
				string[] strs;
				if (a.length > 0)
					strs ~= a;
				if (b.length > 0)
					strs ~= b;
				if (c.length > 0)
					strs ~= c;

				if (strs.length == 0)
					continue;

				combs ~= strs.join("-");
			}
		}
	}

	return combs;
}

string[] getCombinations_alright(string[] as, string[] bs, string[] cs)
{
	string[] combs;

	string[] strs;
	strs.length = 3;

	size_t ind = void;
	foreach (c; as)
	{
		ind = 0;
		if (c.length > 0)
			strs[ind++] = c;

		size_t ind_start1 = ind;
		foreach (b; bs)
		{
			ind = ind_start1;
			if (b.length > 0)
				strs[ind++] = b;

			size_t ind_start2 = ind;
			foreach (a; cs)
			{
				ind = ind_start2;
				if (a.length > 0)
					strs[ind++] = a;

				if (ind > 0)
				{
					combs ~= strs[0..ind].join("-");
				}
			}
		}
	}

	return combs;
}

string[] getCombinations2(string[] as, string[] bs, string[] cs)
{
	string[] combs;

	char[] str;
	str.length = 128;

	size_t ind = void;
	foreach (c; as)
	{
		ind = 0;
		if (c.length > 0)
		{
			str[ind..ind+c.length] = c; ind += c.length;
		}

		size_t ind_start1 = ind;
		foreach (b; bs)
		{
			ind = ind_start1;
			if (b.length > 0)
			{
				if (ind > 0) str[ind++] = '-';
				str[ind..ind+b.length] = b; ind += b.length;
			}

			size_t ind_start2 = ind;
			foreach (a; cs)
			{
				ind = ind_start2;
				if (a.length > 0)
				{
					if (ind > 0) str[ind++] = '-';
					str[ind..ind+a.length] = a; ind += a.length;
				}

				if (ind > 0)
				{
					combs ~= str[0..ind].idup/*.join("-")*/;
				}
			}
		}
	}

	return combs;
}