module cvbuild.semver;

import cvbuild.globals;

import std.string;
import std.algorithm;
import std.algorithm.sorting;
import std.ascii : isDigit, isWhite;
import std.algorithm : sort;

struct SemVer
{
	uint[3] v;
	string prerelease;
	string build;

	int numbers;

	static const SemVer min = SemVer(uint.min, uint.min, uint.min);
	static const SemVer max = SemVer(uint.max, uint.max, uint.max); // this should probably be SemVer(uint.max, 0, 0) ?
	static const SemVer invalid = SemVer(uint.max, uint.max, uint.max);

	this(SemVer other)
	{
		v = other.v;
		numbers = 3;//other.numbers;
		prerelease = other.prerelease;
		build = other.build;
	}

	/*this(uint major, string label = null)
	{
		v = [major, 0, 0];
		parseLabels(label);
		numbers = 1;
	}

	this(uint major, uint minor, string label = null)
	{
		v = [major, minor, 0];
		parseLabels(label);
		numbers = 2;
	}*/

	this(uint major, uint minor, uint patch, string label = null)
	{
		v = [major, minor, patch];
		parseLabels(label);
		numbers = 3;
	}

	this(string semver)
	{
		import std.array : split;
		import std.conv : parse;

		v = [0, 0, 0];
		semver = parseLabels(semver);

		foreach (str; split(semver, "."))
		{
			if (numbers >= 3)
				throw new Exception("failed to parse semver: " ~ semver);

			v[numbers] = parse!(uint)(str);
			numbers++;
		}
		if (numbers == 0)
			throw new Exception("failed to parse semver: " ~ semver);
	}

	private string parseLabels(string label)
	{
		if (!label)
			return null;

		auto plusInd = label.indexOf("+");
		if (plusInd != -1)
		{
			build = label[plusInd+1..$];
			label = label[0..plusInd];
		}

		auto dashInd = label.indexOf("-");
		if (dashInd != -1)
		{
			prerelease = label[dashInd+1..$];
			label = label[0..dashInd];
		}

		// verify valid characters
		import std.ascii;
		foreach (c; prerelease)
		{
			if (!isAlphaNum(c) && c != '.')
				throw new Exception("invalid characters in SemVer pre-release: " ~ prerelease);
		}
		foreach (c; build)
		{
			if (!isAlphaNum(c) && c != '.')
				throw new Exception("invalid characters in SemVer build: " ~ prerelease);
		}
		foreach (c; label)
		{
			if (!isAlphaNum(c) && c != '.')
				throw new Exception("invalid characters in SemVer: " ~ label);
		}

		return label;
	}

	string getLabel()
	{
		string label;
		if (prerelease)
			label ~= "-" ~ prerelease;
		if (build)
			label ~= "+" ~ build;
		return label;
	}

	string toString()
	{
		import std.format;

		string label = getLabel();

		if (numbers >= 3)
			return format!"%u.%u.%u%s"(v[0], v[1], v[2], label);
		if (numbers >= 2)
			return format!"%u.%u%s"(v[0], v[1], label);
		else
			return format!"%u%s"(v[0], label);
	}

	int opCmp(string other) const
	{
		SemVer other_ = other;
		return opCmp(other_);
	}

	int opCmp(SemVer other) const
	{
		if (numbers != other.numbers)
			throw new Exception("unable to compare semver");
		for (int i=0; i<numbers; i++)
		{
			if (v[i] > other.v[i])
				return 1;
			else if (v[i] < other.v[i])
				return -1;
		}

		if (!prerelease && other.prerelease)
			return 1;
		else if (prerelease && !other.prerelease)
			return -1;
		else if (alphaNumSort(other.prerelease, prerelease))
			return 1;
		else if (alphaNumSort(prerelease, other.prerelease))
			return -1;

		return 0;
	}

	bool opEquals(const SemVer other) const
	{
		if (numbers != other.numbers)
			return false;

		for (int i=0; i<numbers; i++)
		{
			if (v[i] != other.v[i])
				return false;
		}

		if (prerelease != other.prerelease)
			return false;

		return true;
	}

	auto opUnary(string op)()
	if (op == "++")
	{
		v[numbers-1]++;
		return this;
	}
}

alias alphaNumSort = (a, b)
{
	import std.conv : parse;
	// quick and dirty version of alphanumerical sorting,
	// assumes the first numbers start at exact same position
	// - 0-btest, 1-atest
	// - test-0-b, test-1-a
	size_t len = min(a.length, b.length);
	size_t i = 0;
	for (; i<len; i++)
	{
		if (a[i] == b[i])
			continue;
		else if (isDigit(a[i]) && isDigit(b[i]))
		{
			string aa = a[i..$];
			string bb = b[i..$];
			int anum = parse!(int)(aa);
			int bnum = parse!(int)(bb);
			return anum < bnum;
		}
		break;
	}

	return a[i..$] < b[i..$]; // characters up to i are equal
	//return a < b;
};

unittest
{
	assert(SemVer("1.0.0") == SemVer(1, 0, 0));
	assert(++SemVer("1.0.0") == SemVer(1, 0, 1));

	assert(SemVer("1.0.1") > SemVer("1.0.0"));
	assert(SemVer("1.0.2") < SemVer("1.0.33"));

	assert(SemVer("1.1.0") > SemVer("1.0.0"));
	assert(SemVer("1.2.0") < SemVer("1.11.0"));

	assert(SemVer("1.2.3") > SemVer("0.9.8"));
	assert(SemVer("1.2.3") < SemVer("2.3.4"));

	//assert(SemVer("1.0.0") < SemVer("1.0"));


	assert(SemVer("1.0.0+stable") == SemVer("1.0.0+master"));
	assert(SemVer("1.0.0-alpha+build.001") == SemVer("1.0.0-alpha+build.002"));
	assert(SemVer("1.0.0-alpha") != SemVer("1.0.0-final"));

	assert(SemVer("1.0.0-aaa") < SemVer("1.0.0-z"));

	assert(SemVer("1.0.0-alpha") < SemVer("1.0.0-alpha.1"));
	assert(SemVer("1.0.0-alpha.1") < SemVer("1.0.0-alpha.beta"));
	assert(SemVer("1.0.0-beta") < SemVer("1.0.0-beta.2"));
	assert(SemVer("1.0.0-beta.2") < SemVer("1.0.0-beta.11"));
	assert(SemVer("1.0.0-beta.11") < SemVer("1.0.0-rc.1"));
	assert(SemVer("1.0.0-rc.1") < SemVer("1.0.0"));

	import std.exception;
	assertThrown(SemVer("2.0.2_2.0.16")); // not a valid version, but dub package directory naming substitutes '+' with '_'

	// invalid characters
	assertThrown(SemVer("1.0.0_"));
	assertThrown(SemVer("1.0.0?"));
	assertThrown(SemVer("1.0.0()"));
	assertThrown(SemVer("1.0.0<>"));
	assertThrown(SemVer("1.0.0\\"));
	assertThrown(SemVer("1.0.0/"));
	assertThrown(SemVer("1.0.0*"));
	assertThrown(SemVer("1.0.0\""));
}

struct SemVerRange
{
	SemVer min = SemVer.max; // inclusive >=
	SemVer max = SemVer.max; // exclusive <
	// special cases:
	// - SemVerRange is invalid when min == max == SemVer.max
	// - exact match only when min == max != SemVer.max

	this(SemVer min, SemVer max)
	{
		this.min = min;
		this.max = max;
	}

	this(string versionSpecifier)
	{
		parse(versionSpecifier);
	}

	bool isValid()
	{
		return min != SemVer.max && min <= max;
	}

	// returns a string representation of the range in form of ">=min <max" (upper limit optional) or "==ver"
	string toString()
	{
		import std.format;

		if (min == SemVer.max)
			return "invalid";
		else if (max == SemVer.max)
			return format!">=%s"(min.toString());
		else if (min == max)
			return format!"==%s"(min.toString());
		else
			return format!">=%s <%s"(min.toString(), max.toString());
	}

	bool satisfies(SemVer ver)
	{
		if (min == max && min != SemVer.max)
			return ver == min;
		return ver >= min && ver < max;
	}

	// narrow down the ranges, returns a common range (or subset) of two ranges
	SemVerRange narrow(SemVerRange other)
	{
		SemVerRange range;
		if (max < other.min || other.max < min)
			return range; // two non-overlapping ranges have nothing in common

		static import std.algorithm;
		range.min = std.algorithm.max(min, other.min);
		range.max = std.algorithm.min(max, other.max);

		if (range.min == range.max)
		{
			// ambiguity: range is now "==1.0.0" but it could also be ">=1.0.0 <1.0.0" which is not valid.
			// the resulting range is valid only if one of the ranges expected an exact match ("==1.0.0").
			if (min != max && other.min != other.max)
				range.min = range.max = SemVer.max; // invalidate range
		}

		return range;
	}

	private void parse(string versionSpecifier)
	{
		// fast path for common cases
		if (versionSpecifier == "*" || versionSpecifier == ">=0.0.0")
		{
			min = SemVer.min;
			max = SemVer.max;
			return;
		}

		size_t parseVersionOperator(size_t pos, string versionSpecifier, ref string operator, ref string ver)
		{
			// skip whitespace
			while (isWhite(versionSpecifier[pos]) && pos < versionSpecifier.length)
				pos++;

			for (size_t startPos = pos; pos < versionSpecifier.length; pos++)
			{
				if (!isDigit(versionSpecifier[pos]))
					continue;

				// found a digit
				operator = versionSpecifier[startPos..pos];
				ver = versionSpecifier[pos..$];
				break;
			}

			if (ver.indexOf(" ") != -1)
				ver = ver[0..ver.indexOf(" ")];

			return pos + ver.length;
		}

		string operator;
		string ver = versionSpecifier;
		size_t pos = 0;

		pos = parseVersionOperator(pos, versionSpecifier, operator, ver);
		min = SemVer(ver);

		if (operator == ">=")
		{ } // as expected
		else if (operator == ">")
			min++;
		else if (operator == "==" || operator == "><=" || operator.length == 0)
			max = min;
		else if (operator == "^") // "head" operator, allows minor updates, freezes major
		{
			if (min.v[0] == 0)
			{
				// special case: major version 0 is not considered stable, so no changes allowed
				max = min;
				max++;
			}
			else
				max = SemVer(min.v[0]+1, 0, 0);
		}
		else if (operator == "~>") // "tail" operator, allows patch updates, freezes minor
		{
			SemVer maxVer = void;
			if (min.numbers == 3)
				max = SemVer(min.v[0], min.v[1]+1, 0);
			else if (min.numbers == 2)
				max = SemVer(min.v[0]+1, 0, 0);
			else if (min.numbers == 1)
				max = SemVer.max; // maybe?
			else
				throw new Exception("invalid version specifier ~>" ~ ver);
		}
		else if (operator == "<")
		{
			max = min;
			min = SemVer.min;
		}
		else if (operator == "<=")
		{
			max = min++;
			min = SemVer.min;
		}
		else
			throw new Exception("unsupported SemVerRange operator: '" ~ operator ~ "'");

		if (min.numbers > 0)
			min.numbers = 3;
		if (max.numbers > 0)
			max.numbers = 3;

		if (pos >= versionSpecifier.length)
			return;

		operator = null;
		ver = versionSpecifier[pos..$];

		pos = parseVersionOperator(pos, versionSpecifier, operator, ver);
		max = SemVer(ver);
		max.numbers = 3;

		if (operator == "<")
		{ } // as expected
		else if (operator == "<=")
			max++;
		else
			throw new Exception("unsupported SemVerRange operator: '" ~ operator ~ "'");

		if (max <= min)
			throw new Exception("invalid SemVerRange: >=" ~ min.toString() ~ " <" ~ max.toString());
	}

	// string maxSatisfying(string[] versions)
	// string minSatisfying(string[] versions)
}

unittest
{
	assert(SemVerRange(">=0.0.0").toString() == ">=0.0.0");
	assert(SemVerRange("*").toString() == ">=0.0.0");

	assert(SemVerRange(">=1.2.3").toString() == ">=1.2.3");
	assert(SemVerRange(">1.2.3").toString() == ">=1.2.4");

	assert(SemVerRange("==1.2.3").toString() == "==1.2.3");
	assert(SemVerRange("1.2.3").toString() == "==1.2.3");

	assert(SemVerRange("~>1.2.3").toString() == ">=1.2.3 <1.3.0");
	assert(SemVerRange("~>1.2").toString() == ">=1.2.0 <2.0.0");
	assert(SemVerRange("~>1").toString() == ">=1.0.0"); //?


	assert(SemVerRange("^1.2.3").toString() == ">=1.2.3 <2.0.0");
	assert(SemVerRange("^1.2").toString() == ">=1.2.0 <2.0.0");
	assert(SemVerRange("^0.4.1").toString() == ">=0.4.1 <0.4.2");
	assert(SemVerRange("^0.0.6").toString() == ">=0.0.6 <0.0.7");

	// weird ones
	assert(SemVerRange(">1.2.3").toString() == ">=1.2.4");
	assert(SemVerRange("<1.2.3").toString() == ">=0.0.0 <1.2.3");

	// TODO: "><=" operator
	// TODO: test with branches and prerelease tags

	assert(SemVerRange(">=1.2.3 <1.4.0").toString() == ">=1.2.3 <1.4.0");
	assert(SemVerRange(">=1.2.3 <=1.4.0").toString() == ">=1.2.3 <1.4.1");

	import std.exception;
	assertThrown(SemVerRange(">=2.0.0 <1.9.9"));
	assertThrown(SemVerRange(">=2.0.0 <2.0.0"));

	auto range1 = SemVerRange(">=1.0.1 <2.1.1");
	assert(range1.isValid());
	assert(!range1.satisfies(SemVer("1.0.0")));
	assert(range1.satisfies(SemVer("1.0.1")));
	assert(range1.satisfies(SemVer("1.99.99")));
	assert(range1.satisfies(SemVer("2.0.0")));
	assert(range1.satisfies(SemVer("2.1.0")));
	assert(!range1.satisfies(SemVer("2.1.1")));
	assert(!range1.satisfies(SemVer("3.0.1")));

	auto range2 = SemVerRange("==1.0.1");
	assert(range2.isValid());
	assert(range2.satisfies(SemVer("1.0.1")));
	assert(!range2.satisfies(SemVer("1.0.0")));
	assert(!range2.satisfies(SemVer("1.0.2")));

	assert(!SemVerRange(SemVer("2.0.0"), SemVer("1.0.0")).isValid());
	assert(!SemVerRange().isValid());

	auto range3 = SemVerRange(">=1.1.1 <4.0.0");
	assert(range3.narrow(SemVerRange(">=1.3.0 <3.0.0")).toString() == ">=1.3.0 <3.0.0");
	assert(range3.narrow(SemVerRange(">=1.3.1 <7.0.0")).toString() == ">=1.3.1 <4.0.0");
	assert(range3.narrow(SemVerRange("==1.5.0")).toString() == "==1.5.0");

	assert(!range3.narrow(SemVerRange(">=0.1.0 <1.0.0")).isValid());
	assert(!range3.narrow(SemVerRange("==0.9.9")).isValid());
}

void parseVersionSpecifier(string versionSpecifier, ref SemVer ver1, ref string operator1, ref SemVer ver2, ref string operator2)
{
	if (versionSpecifier == "*")
	{
		ver1 = SemVer.min;
		operator1 = ">=";
		ver2 = SemVer.max;
		operator2 = "<";
		return;
	}
	else if (isDigit(versionSpecifier[0]))
	{
		ver1 = SemVer(versionSpecifier);
		operator1 = "==";
		return;
	}

	string semVer_str = versionSpecifier;
	string semVerOther_str = null;
	auto wInd = semVer_str.indexOf(" ");
	if (wInd != -1)
	{
		semVerOther_str = semVer_str[wInd+1..$];
		semVer_str = semVer_str[0..wInd];
	}

	string operator;
	for (int i=0; i<semVer_str.length; i++)
	{
		if (isDigit(semVer_str[i]))
		{
			operator = semVer_str[0..i];
			semVer_str = semVer_str[i..$];
			break;
		}
	}
	string operatorOther;
	for (int i=0; i<semVerOther_str.length; i++)
	{
		if (isDigit(semVerOther_str[i]))
		{
			operatorOther = semVerOther_str[0..i];
			semVerOther_str = semVerOther_str[i..$];
			break;
		}
	}

	ver1 = SemVer(semVer_str);
	operator1 = operator.length > 0 ? operator : null;
	if (semVerOther_str)
	{
		ver2 = SemVer(semVerOther_str);
		operator2 = operatorOther.length > 0 ? operatorOther : null;
	}
	else
	{
		ver2 = SemVer.max;
		operator2 = "<";
	}

	if (operator == "~>")
	{
		SemVer maxVer = void;
		if (ver1.numbers == 3)
			maxVer = SemVer(ver1.v[0], ver1.v[1]+1, 0);
		else if (ver1.numbers == 2)
			maxVer = SemVer(ver1.v[0]+1, 0, 0);
		else if (ver1.numbers == 1)
			maxVer = SemVer.max; // maybe?
		else
			errorln("invalid version specifier ~>", ver1.toString()); //return choosePackage(packageVersions, "*");

		operator1 = ">=";
		ver1 = SemVer(ver1);

		//assert(operator2 == null);
		//assert(ver2 == SemVer.max);
		operator2 = "<";
		ver2 = maxVer;
		//return choosePackage(packageVersions, SemVer(ver1.v[0], ver1.v[1], ver1.v[2], ver1.label), ">=", maxVer, "<");
	}
}

string choosePackage(string[] packageVersions, string versionSpecifier)
{
	// handle some common cases
	if (versionSpecifier == "*" || versionSpecifier == ">=0.0.0")
		return choosePackage(packageVersions, SemVer(0, 0, 0), ">=");
	else if (versionSpecifier.startsWith("=="))
	{
		// REMOVEME
		string packageVer = versionSpecifier[2..$];
		foreach (verFull; packageVersions)
		{
			if (verFull == packageVer)
				return verFull;
		}
		return null;
	}
	else if (isDigit(versionSpecifier[0])) // "==" omitted
	{
		foreach (verFull; packageVersions)
		{
			if (verFull == versionSpecifier)
				return verFull;
		}
		return null;
	}
	else if (versionSpecifier.startsWith("~master")) // deprecated?
	{
		foreach (verFull; packageVersions)
		{
			if (verFull == "master")
				return "master";
		}
		return null;
	}

	SemVer semVer;
	string operator;
	SemVer semVer2;
	string operator2;
	parseVersionSpecifier(versionSpecifier, semVer, operator, semVer2, operator2);

	return choosePackage(packageVersions, semVer, operator, semVer2, operator2);
}

string choosePackage(string[] packageVersions, SemVer semVer, string operator, SemVer semVerOther = SemVer.max, string operatorOther = null)
{
	/*if (operator == "~>")
	{
		SemVer maxVer = void;
		if (semVer.numbers == 3)
			maxVer = SemVer(semVer.v[0], semVer.v[1]+1, 0);
		else if (semVer.numbers == 2)
			maxVer = SemVer(semVer.v[0]+1, 0, 0);
		else if (semVer.numbers == 1)
			maxVer = SemVer.max; // maybe?
		else
			errorln("invalid version specifier ~>", semVer.toString()); //return choosePackage(packageVersions, "*");

		return choosePackage(packageVersions, SemVer(semVer.v[0], semVer.v[1], semVer.v[2], semVer.label), ">=", maxVer, "<");
	}*/
	if (operator == "==")
	{
		string packageVer = semVer.toString();
		foreach (ver; packageVersions)
		{
			if (ver == packageVer) // fast path
				return ver;

			auto bInd = ver.indexOf("_"); // ignore build
			if (bInd != -1)
				ver = ver[0..bInd];

			SemVer pSemVer = SemVer(ver);
			if (pSemVer == semVer)
				return ver;
		}

		/*if (semVer.getLabel())
		{
			SemVer altVer = semVer;
			altVer.label = null;
			altVer.v[2] += 1;
			assert(altVer != semVer);
			return choosePackage(packageVersions, altVer, operator, semVerOther, operatorOther);
		}*/

		return null;
	}
	else if (operator == ">" || operator == ">=")
	{
		bool matchEqual = operator == ">=";

		bool maxEqual = operatorOther && operatorOther.startsWith(">=");
		SemVer maxver = operatorOther ? semVerOther : SemVer.max;
		//auto mInd = psemverStr.indexOf("<");

		struct Match
		{
			SemVer semver;
			string name;

			int opCmp(Match other)
			{
				return semver.opCmp(other.semver);
			}
		}
		Match[] found;

		foreach (verFull; packageVersions)
		{
			string ver = verFull;

			auto bInd = ver.indexOf("_"); // ignore build
			if (bInd != -1)
				ver = ver[0..bInd];

			if (ver == "master") // FIXME?
				continue;

			SemVer pSemVer = SemVer(ver);
			//outputln("semver: ", semver);

			if (pSemVer > maxver)
				continue;
			else if (maxEqual /*&& pSemVer == maxver*/)
			{}
			else if (!maxEqual && pSemVer != maxver)
			{}
			else // (semver == maxver)
				continue;

			if (pSemVer < semVer)
				continue;
			else if (matchEqual /*&& pSemVer == semVer*/)
				found ~= Match(pSemVer, verFull);
			else if (!matchEqual && pSemVer != semVer)
				found ~= Match(pSemVer, verFull);
			//else // (pSemVer == semVer)
			//	continue;
		}
		found = found.sort().reverse.release;
		if (found.length > 0)
			return found[0].name;//found = found[0..1];
	}
	else
		errorln("not implemented semver operator: '", operator, "'");

	return null;
}
