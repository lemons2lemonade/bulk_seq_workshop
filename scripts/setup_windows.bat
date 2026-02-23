@echo off
setlocal
cd /d "%~dp0\.."

echo ============================================================
echo Bulk-seq workshop setup (Windows)
echo Repo root: %cd%
echo ============================================================
echo.

echo [BAT] powershell location:
where powershell
echo.

echo [BAT] launching setup_windows.ps1...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command ^
  "& { ^
      Write-Host '[PS] Starting setup...' -ForegroundColor Cyan; ^
      Write-Host ('[PS] Script path: {0}' -f (Resolve-Path '.\scripts\setup_windows.ps1')) -ForegroundColor Cyan; ^
      & .\scripts\setup_windows.ps1 ^
    }"

echo.
echo [BAT] PowerShell process returned (unexpected). Press any key to close.
pause >nul