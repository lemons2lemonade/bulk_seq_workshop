#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Always-on logging ---
$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("launch_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "Logging to: $LogFile"

trap {
  Write-Host ""
  Write-Host "==============================================" -ForegroundColor Red
  Write-Host "LAUNCH FAILED ❌" -ForegroundColor Red
  Write-Host "==============================================" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "Log saved at: $LogFile" -ForegroundColor Yellow
  try { Stop-Transcript | Out-Null } catch {}
  Write-Host "Press Enter to close..." -ForegroundColor Yellow
  [void](Read-Host)
  exit 1
}

function Banner([string]$msg) {
  Write-Host ""
  Write-Host "============================================================"
  Write-Host $msg
  Write-Host "============================================================"
}

# --- Guard: do not run as Administrator ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
  throw "Please do NOT run as Administrator. Close this window and run launch_windows.bat normally."
}

# --- Resolve repo + notebook ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

$EnvName  = "rpkm-workshop"
$Notebook = Join-Path $RepoRoot "notebooks\workshop.ipynb"

if (!(Test-Path $Notebook)) { throw "Missing notebook: $Notebook" }

Banner "Launching workshop notebook (Windows)"
Write-Host "Repo root: $RepoRoot"
Write-Host "Notebook:  $Notebook"

# --- Find conda (prefer PATH, fallback to Miniforge default) ---
$MiniforgeDir = Join-Path $env:USERPROFILE "miniforge3"
$CondaExe     = Join-Path $MiniforgeDir "Scripts\conda.exe"

$Conda = $null
if (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
} elseif (Test-Path $CondaExe) {
  $Conda = $CondaExe
} else {
  throw "conda not found. Please run scripts\setup_windows.bat first."
}

Write-Host "Using conda: $Conda"
& $Conda --version | Out-Host

# --- Check env exists ---
$EnvList = & $Conda env list
if ($EnvList -notmatch "^\s*$EnvName\s") {
  throw "Conda env '$EnvName' not found. Please run scripts\setup_windows.bat first."
}

# --- Launch ---
Set-Location $RepoRoot
Write-Host ""
Write-Host "Launching JupyterLab..." -ForegroundColor Green
& $Conda run -n $EnvName jupyter lab $Notebook

Write-Host ""
Write-Host "Jupyter exited. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)