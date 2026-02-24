@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%launch_windows.ps1"

echo ============================================================
echo Bulk-seq workshop launch (Windows)
echo ============================================================
echo [BAT] Script: "%PS1%"
echo.

set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%PS1%" (
  echo ERROR: Cannot find "%PS1%"
  echo Press any key to exit...
  pause >nul
  exit /b 1
)

echo [BAT] Unblocking PS1 (if needed)...
%PWSH% -NoProfile -Command "try { Unblock-File -Path '%PS1%' -ErrorAction SilentlyContinue } catch {}" >nul 2>nul

echo [BAT] Launching PowerShell...
echo.

%PWSH% -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PS1%"

echo.
echo [BAT] PowerShell exited. Press any key to close...
pause >nul