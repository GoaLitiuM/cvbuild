@echo off
pushd %CD%

cd tests

dmd runTests.d -m64 -g -debug
IF %ERRORLEVEL% EQU 0 (
	runTests.exe %*
)

popd