@echo off
setlocal EnableExtensions

REM Move to repo root (parent of scripts/)
cd /d "%~dp0.."

echo ============================================================
echo Bulk-seq workshop setup (Windows)
echo Repo root: %CD%
echo ============================================================
echo.

set "PS1=%CD%\scripts\setup_windows.ps1"

if not exist "%PS1%" (
  echo [BAT] ERROR: setup_windows.ps1 not found at:
  echo       "%PS1%"
  echo.
  pause
  exit /b 1
)

REM Prefer Windows PowerShell 5.1 (always present) for max compatibility
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

echo [BAT] PowerShell:
echo       %PSEXE%
echo.
echo [BAT] launching setup_windows.ps1...
echo.

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo [BAT] Setup exited with code %EC%.
  echo [BAT] If a window closed too fast, run this BAT from cmd.exe to see output.
  echo.
  pause
  exit /b %EC%
)

echo.
echo [BAT] Setup completed successfully.
pause
exit /b 0