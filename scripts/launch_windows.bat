@echo off
setlocal EnableExtensions

REM Move to repo root
cd /d "%~dp0.."

echo ============================================================
echo Bulk-seq workshop launch (Windows)
echo Repo root: %CD%
echo ============================================================
echo.

set "PS1=%CD%\scripts\launch_windows.ps1"

if not exist "%PS1%" (
  echo [BAT] ERROR: launch_windows.ps1 not found at:
  echo       "%PS1%"
  echo.
  pause
  exit /b 1
)

set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

echo [BAT] PowerShell:
echo       %PSEXE%
echo.
echo [BAT] launching launch_windows.ps1...
echo.

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo [BAT] Launch exited with code %EC%.
  echo.
  pause
  exit /b %EC%
)

echo.
echo [BAT] Launch completed.
pause
exit /b 0