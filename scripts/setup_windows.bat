@echo off
setlocal enabledelayedexpansion

REM Run setup script from this folder, regardless of where user double-clicks from.
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%setup_windows.ps1"

echo ============================================================
echo Bulk-seq workshop setup (Windows)
echo ============================================================
echo [BAT] Script: "%PS1%"
echo.

REM Use Windows PowerShell 5.1 explicitly (works everywhere)
set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%PS1%" (
  echo ERROR: Cannot find "%PS1%"
  echo Press any key to exit...
  pause >nul
  exit /b 1
)

REM Unblock the PS1 in case it came from the internet/zip
echo [BAT] Unblocking PS1 (if needed)...
%PWSH% -NoProfile -Command "try { Unblock-File -Path '%PS1%' -ErrorAction SilentlyContinue } catch {}" >nul 2>nul

echo [BAT] Launching PowerShell...
echo.

%PWSH% -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PS1%"

echo.
echo [BAT] PowerShell exited. Press any key to close...
pause >nul