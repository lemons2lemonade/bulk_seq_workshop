@echo off
setlocal 
cd /d "%~dp0\.."
powershell -NoProfile -NoExit -ExecutionPolicy Bypass -File ".\scripts\setup_windows.ps1"