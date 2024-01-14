module app;

int main()
{
	import std.process;

	version (Windows)
		enum ext = ".exe";
	else
		enum ext = "";

	return wait(spawnProcess("./sub" ~ ext));
}