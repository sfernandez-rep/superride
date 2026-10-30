@echo off
rem Upstream R-session test suite (rsession --run-tests) against the feature build.
rem SPDX-License-Identifier: AGPL-3.0-only
rem Usage: tools\superrstudio\test-session.cmd [experimental]
rem   "experimental" also sets SUPER_RSTUDIO_EXPERIMENTAL=1 so the SuperRStudio
rem   module sources its R code during session initialization.
setlocal
for %%I in ("%~dp0..\..") do set "SUPER_R_ROOT=%%~fI"
set "BUILD=%SUPER_R_ROOT%\build\superrstudio-windows"
call "%~dp0enter-windows.cmd" >nul
if errorlevel 1 exit /b 1
set "R_HOME=C:\R\R-4.6.1"
set "R_DOC_DIR=C:\R\R-4.6.1\doc"
set "R_LIB_DIR=C:\R\R-4.6.1\lib"
set "PATH=C:\R\R-4.6.1\bin\x64;%PATH%"
set "R_PROFILE_USER=NUL"
set "R_ENVIRON_USER=NUL"
set "RSTUDIO_TESTS_HELPER=1"
set "SUPER_RSTUDIO_EXPERIMENTAL="
if /i "%~1"=="experimental" set "SUPER_RSTUDIO_EXPERIMENTAL=1"
for /f %%G in ('powershell.exe -NoProfile -NonInteractive -Command "[guid]::NewGuid().ToString()"') do set "TEST_ROOT=%TEMP%\superrstudio-session-%%G"
if not defined TEST_ROOT exit /b 1
set "RSTUDIO_DATA_HOME=%TEST_ROOT%\data"
set "RSTUDIO_CONFIG_HOME=%TEST_ROOT%\config"
mkdir "%RSTUDIO_DATA_HOME%\client-state"
mkdir "%RSTUDIO_CONFIG_HOME%"
cd /d "%SUPER_R_ROOT%"
"%BUILD%\src\cpp\session\rsession-utf8.exe" --run-tests --config-file="%BUILD%\src\cpp\conf\rdesktop-dev.conf"
set "RESULT=%ERRORLEVEL%"
rmdir /s /q "%TEST_ROOT%" 2>nul
exit /b %RESULT%
