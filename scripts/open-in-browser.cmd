@echo off
setlocal

REM This launcher runs the PowerShell version from Windows Command Prompt.
REM Usage:
REM   open-in-browser.cmd
REM   open-in-browser.cmd 9000

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%open-in-browser.ps1"
set "PORT=%~1"

if not exist "%PS1_SCRIPT%" (
  echo Could not find %PS1_SCRIPT%
  exit /b 1
)

if "%PORT%"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -Port %PORT%
)

set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
  echo.
  echo Launcher exited with code %EXIT_CODE%.
)

exit /b %EXIT_CODE%