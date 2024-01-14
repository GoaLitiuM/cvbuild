module cvbuild.dub.command;

import std.process;

import std.string : strip;
import std.array : join;

struct DubResult
{
	int returnCode;
	string output;
}

DubResult dubRun(string[] args, string cwd = null)
{
	DubResult result;

	ProcessPipes dubProcess = pipeProcess(["dub"] ~ args, Redirect.all, null, Config.none, cwd);
	result.returnCode = wait(dubProcess.pid);

	string[] lines;
	foreach (line; dubProcess.stdout.byLine)
		lines ~= strip(line).idup;
	foreach (line; dubProcess.stderr.byLine)
		lines ~= strip(line).idup;
	result.output = lines.join("\n");

	return result;
}
