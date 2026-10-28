@echo off
rem Call this from cmd.exe to configure this shell for the pinned Windows build.
for %%I in ("%~dp0..\..") do set "SUPER_R_ROOT=%%~fI"
if not defined RSTUDIO_TOOLS_ROOT for %%I in ("%SUPER_R_ROOT%\..\rstudio-tools") do set "RSTUDIO_TOOLS_ROOT=%%~fI"
if not defined LIBR_HOME set "LIBR_HOME=C:\R\R-3.6.3"
if not defined RSTUDIO_WHICH_R set "RSTUDIO_WHICH_R=C:\R\R-4.6.1\bin\x64\R.exe"
if not defined WIN32_SDK_VERSION set "WIN32_SDK_VERSION=10.0.26100.0"
rem Native Windows R and Perl do not accept the inherited MSYS C.UTF-8 locale.
if /i "%LC_ALL%"=="C.UTF-8" set "LC_ALL="
if /i "%LC_CTYPE%"=="C.UTF-8" set "LC_CTYPE="
if /i "%LANG%"=="C.UTF-8" set "LANG="

set "PATH=%SUPER_R_ROOT%\.cache\superrstudio\tools\cmake-4.3.4-windows-x86_64\bin;%SUPER_R_ROOT%\.cache\superrstudio\tools\ninja-1.13.1;%LIBR_HOME%\bin\x64;C:\Strawberry\perl\bin;C:\Program Files (x86)\NSIS;%PATH%"
if exist "%USERPROFILE%\scoop\apps\ant\current\bin\ant.bat" (
  set "ANT_HOME=%USERPROFILE%\scoop\apps\ant\current"
  set "PATH=%USERPROFILE%\scoop\apps\ant\current\bin;%PATH%"
)
if exist "%LocalAppData%\Programs\Python\Python313\python.exe" set "PYTHON=%LocalAppData%\Programs\Python\Python313\python.exe"
if exist "%ProgramFiles%\Python313\python.exe" set "PYTHON=%ProgramFiles%\Python313\python.exe"
if defined PYTHON for %%I in ("%PYTHON%") do set "PATH=%%~dpI;%PATH%"

pushd "%SUPER_R_ROOT%"
call src\cpp\tools\windows-dev.cmd
if errorlevel 1 goto failed
popd
rem Match MSVC's UTF-8 diagnostics when CMake probes localized include prefixes.
chcp 65001 >nul
set "PATH=%JAVA_HOME%\bin;%RSTUDIO_TOOLS_ROOT%\dependencies\common\node\%RSTUDIO_NODE_VERSION%;%PATH%"
where /q cl.exe
if errorlevel 1 exit /b 1
where /q R.exe
if errorlevel 1 exit /b 1
where /q cmake.exe
if errorlevel 1 exit /b 1
where /q ninja.exe
if errorlevel 1 exit /b 1
echo SuperRStudio Windows build environment configured for this shell.
exit /b 0

:failed
popd
exit /b 1
