void bug()
{
	// assertion failure in dmd.astbase
	string allDeps;
	allDeps ~= null
	if (allDeps == null)
	{
	}
}