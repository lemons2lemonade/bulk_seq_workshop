#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Resolve paths early ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

# --- Logging ---
$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("launch_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "Logging to: $LogFile"

trap {
  Write-Host ""
  Write-Host "==============================================" -ForegroundColor Red
  Write-Host "LAUNCH FAILED" -ForegroundColor Red
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

function Run-Exe([string]$Label, [string]$Exe, [string[]]$Args) {
  Write-Host ">> $Label"
  & $Exe @Args | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "$Label failed (exit code $LASTEXITCODE)" }
}

$EnvName  = "rpkm-workshop"
$Notebook = Join-Path $RepoRoot "notebooks\workshop.ipynb"

Banner "Workshop launch (Windows) - JupyterLab"
Write-Host "Repo root: $RepoRoot"
Write-Host "Notebook:  $Notebook"
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)

if (!(Test-Path $Notebook)) {
  throw "Notebook not found: $Notebook"
}

# --- Find conda (prefer our known Miniforge install) ---
$Conda = $null
$CondaExe = "C:\Tools\miniforge3\Scripts\conda.exe"

if (Test-Path $CondaExe) {
  $Conda = $CondaExe
} elseif (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
} else {
  throw "conda not found. Please run scripts\setup_windows.bat first."
}

Write-Host "Using conda: $Conda"
& $Conda --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw "conda --version failed (exit code $LASTEXITCODE)" }

# Quick sanity: env exists and can run python
Run-Exe "conda run sanity" $Conda @("run","-n",$EnvName,"python","-c","import sys; print('Python OK:', sys.version.split()[0])")

# Launch JupyterLab
Set-Location $RepoRoot
Run-Exe "jupyter lab" $Conda @("run","-n",$EnvName,"jupyter","lab",$Notebook)

Write-Host ""
Write-Host "Jupyter exited. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)