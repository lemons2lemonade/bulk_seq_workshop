#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Always-on logging ---
$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("setup_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "Logging to: $LogFile"

# --- Trap any error (keeps window open) ---
trap {
  Write-Host ""
  Write-Host "==============================================" -ForegroundColor Red
  Write-Host "SETUP FAILED" -ForegroundColor Red
  Write-Host "==============================================" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "Log saved at: $LogFile" -ForegroundColor Yellow
  try { Stop-Transcript | Out-Null } catch {}
  Write-Host "Press Enter to close..." -ForegroundColor Yellow
  [void](Read-Host)
  exit 1
}

function Step([int]$i, [int]$n, [string]$msg) {
  Write-Host ""
  Write-Host ("[Step {0}/{1}] {2}" -f $i, $n, $msg)
  Write-Host "------------------------------------------------------------"
}

function Banner([string]$msg) {
  Write-Host ""
  Write-Host "============================================================"
  Write-Host $msg
  Write-Host "============================================================"
}

# --- Resolve paths ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

$EnvYml   = Join-Path $RepoRoot "environment.workshop.yml"
$Notebook = Join-Path $RepoRoot "notebooks\workshop.ipynb"

if (!(Test-Path $EnvYml))   { throw "Missing environment file: $EnvYml" }
if (!(Test-Path $Notebook)) { throw "Missing notebook: $Notebook" }

Banner "Workshop setup (Windows) — automatic install + env + Jupyter"
Write-Host "Repo root: $RepoRoot"
Write-Host "Env file:  $EnvYml"
Write-Host "Notebook:  $Notebook"
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)

# --- Guard: do not run as Administrator (workshop installs per-user) ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
  throw "Please do NOT run as Administrator. Close this window and run setup_windows.bat normally (per-user install)."
}

# --- DNS sanity check ---
try {
  $null = Resolve-DnsName "github.com" -ErrorAction Stop
  Write-Host "Network/DNS: OK (github.com resolves)"
} catch {
  throw "Network/DNS check failed: cannot resolve github.com."
}

$TOTAL = 6

# Step 1/6: Ensure conda (install Miniforge if missing)
Step 1 $TOTAL "Ensuring conda is available (Miniforge if needed)"
$MiniforgeDir = Join-Path $env:USERPROFILE "miniforge3"
$CondaExe      = Join-Path $MiniforgeDir "Scripts\conda.exe"

$Conda = $null
if (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
} elseif (Test-Path $CondaExe) {
  $Conda = $CondaExe
} else {
  Write-Host "conda not found — installing Miniforge (no admin required)"
  $Installer = Join-Path $env:TEMP "Miniforge3-Windows-x86_64.exe"
  $Url = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"
  Invoke-WebRequest -Uri $Url -OutFile $Installer

  $p = Start-Process -FilePath $Installer -ArgumentList @("/S", "/D=$MiniforgeDir") -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Miniforge installer failed with exit code $($p.ExitCode)" }
  if (!(Test-Path $CondaExe)) { throw "Miniforge installed but conda not found at $CondaExe" }

  $Conda = $CondaExe
}

Write-Host "Using conda: $Conda"
& $Conda --version | Out-Host

# Step 2/6: Ensure mamba (install only if missing)
Step 2 $TOTAL "Ensuring mamba is available (install only if missing)"
$Mamba = $null
if (Get-Command mamba -ErrorAction SilentlyContinue) {
  $Mamba = "mamba"
} else {
  $BasePrefix = & $Conda info --base
  $Candidate  = Join-Path $BasePrefix "Scripts\mamba.exe"
  if (Test-Path $Candidate) {
    $Mamba = $Candidate
  } else {
    Write-Host "mamba not found — installing into base env"
    & $Conda install -n base -c conda-forge -y mamba | Out-Host
    if (Test-Path $Candidate) { $Mamba = $Candidate } else { throw "mamba installation failed" }
  }
}

Write-Host "Using mamba: $Mamba"
& $Mamba --version | Out-Host

# Step 3/6: Create/update env
Step 3 $TOTAL "Creating/updating env 'rpkm-workshop' (can take a few minutes)"
& $Mamba env update -n rpkm-workshop -f $EnvYml --prune | Out-Host

# Step 4/6: Smoke test + triage printout (no here-strings; avoids parsing/encoding issues)
Step 4 $TOTAL "Smoke test + triage printout"

$SmokePy = Join-Path $env:TEMP "bulk_seq_workshop_smoke_test.py"
$SmokeLines = @(
  'import sys, platform',
  'import numpy, pandas, scipy, sklearn, matplotlib',
  '',
  'print("SMOKE TEST OK")',
  'print("PY:", sys.version.replace("\n"," "))',
  'print("PLATFORM:", platform.platform())',
  'print("numpy:", numpy.__version__)',
  'print("pandas:", pandas.__version__)',
  'print("scipy:", scipy.__version__)',
  'print("sklearn:", sklearn.__version__)',
  'print("matplotlib:", matplotlib.__version__)'
)
Set-Content -Path $SmokePy -Value $SmokeLines -Encoding UTF8

& $Conda run -n rpkm-workshop python $SmokePy | Out-Host
# Step 5/6: Register kernel
Step 5 $TOTAL "Registering Jupyter kernel 'rpkm-workshop'"
& $Conda run -n rpkm-workshop python -m ipykernel install --user --name rpkm-workshop --display-name rpkm-workshop | Out-Host

# Step 6/6: Launch JupyterLab + notebook
Step 6 $TOTAL "Launching JupyterLab + opening notebooks/workshop.ipynb"
Write-Host ""
Write-Host "SUCCESS - Environment ready. Launching the notebook now…" -ForegroundColor Green

Set-Location $RepoRoot
& $Conda run -n rpkm-workshop jupyter lab $Notebook

Write-Host ""
Write-Host "Jupyter exited. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)