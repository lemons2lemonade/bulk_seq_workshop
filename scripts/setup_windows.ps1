#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Resolve paths early ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

# --- Create all directories we depend on (fail-fast if we can't) ---
$TmpRoot = Join-Path $env:TEMP "bulk_seq_workshop_tmp"
New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null

$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Workshop-safe, no-space install root for Miniforge
$ToolsRoot = "C:\Tools"
$MiniforgeDir = Join-Path $ToolsRoot "miniforge3"
New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null

# --- Always-on logging ---
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

# --- Helpers for robust installs ---
function Quarantine-Dir([string]$Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $q = "${Path}.quarantine_${stamp}"
    Write-Host "Quarantining: $Path"
    Write-Host "        to: $q"
    try {
      Rename-Item -Path $Path -NewName (Split-Path -Leaf $q) -ErrorAction Stop
    } catch {
      Write-Host "Rename failed; attempting move..." -ForegroundColor Yellow
      Move-Item -Path $Path -Destination $q -Force
    }
  }
}

function Ensure-ParentDir([string]$Path) {
  $parent = Split-Path -Parent $Path
  if ($parent -and !(Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
}

function Run-Exe([string]$Label, [string]$Exe, [string[]]$Args) {
  Write-Host ">> $Label"
  & $Exe @Args | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed (exit code $LASTEXITCODE)"
  }
}

# --- Paths & inputs ---
$EnvYml   = Join-Path $RepoRoot "environment.workshop.yml"
$Notebook = Join-Path $RepoRoot "notebooks\workshop.ipynb"

if (!(Test-Path $EnvYml))   { throw "Missing environment file: $EnvYml" }
if (!(Test-Path $Notebook)) { throw "Missing notebook: $Notebook" }

# Environment name MUST match environment.workshop.yml "name:"
$EnvName = "rpkm-workshop"

Banner "Workshop setup (Windows) - automatic install + env + Jupyter"
Write-Host "Repo root: $RepoRoot"
Write-Host "Env file:  $EnvYml"
Write-Host "Notebook:  $Notebook"
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)

# --- Guard: do not run as Administrator (workshop installs per-user) ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
  throw "Please do NOT run as Administrator. Close this window and run setup normally (per-user install)."
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

# Paths that may exist from older attempts (often with spaces in user profile)
$UserProfileMiniforge = Join-Path $env:USERPROFILE "miniforge3"
$UserProfileMambaforge = Join-Path $env:USERPROFILE "mambaforge"
$UserProfileMiniconda  = Join-Path $env:USERPROFILE "miniconda3"
$UserProfileAnaconda   = Join-Path $env:USERPROFILE "anaconda3"

# Target no-space install
$CondaExe = Join-Path $MiniforgeDir "Scripts\conda.exe"

# 1) If conda is already on PATH, use it and skip install
$Conda = $null
if (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
}

# 2) Otherwise, if our target conda exists, use it
if (-not $Conda -and (Test-Path $CondaExe)) {
  $Conda = $CondaExe
}

# 3) Otherwise, clean up known-bad leftovers and install fresh into C:\Tools\miniforge3
if (-not $Conda) {

  # If our target dir exists but conda.exe is missing, it's a partial install -> quarantine it
  if ((Test-Path $MiniforgeDir) -and !(Test-Path $CondaExe)) {
    Write-Host "Detected partial Miniforge at target location (missing conda.exe)." -ForegroundColor Yellow
    Quarantine-Dir $MiniforgeDir
  }

  # Quarantine old user-profile installs
  foreach ($p in @($UserProfileMiniforge, $UserProfileMambaforge, $UserProfileMiniconda, $UserProfileAnaconda)) {
    if (Test-Path $p) {
      Write-Host "Detected old conda install in user profile: $p" -ForegroundColor Yellow
      Quarantine-Dir $p
    }
  }

  Write-Host "conda not found - installing Miniforge (no admin required)"
  Write-Host "Miniforge target: $MiniforgeDir"

  if ($MiniforgeDir -match "\s") {
    throw "Internal error: MiniforgeDir contains spaces: $MiniforgeDir"
  }

  # Download installer into our dedicated temp directory; re-download if suspiciously small
  $Installer = Join-Path $TmpRoot "Miniforge3-Windows-x86_64.exe"
  $Url = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"

  if (Test-Path $Installer) {
    $len = (Get-Item $Installer).Length
    if ($len -lt 10MB) {
      Write-Host "Found existing installer but it looks incomplete ($len bytes). Removing..." -ForegroundColor Yellow
      Remove-Item -Force $Installer
    }
  }

  if (!(Test-Path $Installer)) {
    Write-Host "Downloading Miniforge installer..."
    Invoke-WebRequest -Uri $Url -OutFile $Installer
  }

  Ensure-ParentDir $MiniforgeDir

  Write-Host "Running installer..."
  $p = Start-Process -FilePath $Installer -ArgumentList @("/S", "/D=$MiniforgeDir") -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Miniforge installer failed with exit code $($p.ExitCode)" }
  if (!(Test-Path $CondaExe)) { throw "Miniforge installed but conda not found at $CondaExe" }

  $Conda = $CondaExe
}

Write-Host "Using conda: $Conda"
& $Conda --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw "conda version check failed (exit code $LASTEXITCODE)" }

# Step 2/6: Ensure mamba (install only if missing)
Step 2 $TOTAL "Ensuring mamba is available (install only if missing)"

function Find-Mamba([string]$BasePrefix) {
  $candidates = @(
    (Join-Path $BasePrefix "Scripts\mamba.exe"),
    (Join-Path $BasePrefix "Library\bin\mamba.exe"),
    (Join-Path $BasePrefix "condabin\mamba.bat")
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

$BasePrefix = & $Conda info --base
$Mamba = $null

if (Get-Command mamba -ErrorAction SilentlyContinue) {
  $Mamba = "mamba"
} else {
  $Mamba = Find-Mamba $BasePrefix
  if (-not $Mamba) {
    Write-Host "mamba not found - installing into base env"
    Run-Exe "conda install mamba" $Conda @("install","-n","base","-c","conda-forge","-y","mamba")
    $Mamba = Find-Mamba $BasePrefix
    if (-not $Mamba) {
      throw "mamba install reported success but executable was not found under base prefix: $BasePrefix"
    }
  }
}

Write-Host "Using solver: $Mamba"
& $Mamba --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw "mamba version check failed (exit code $LASTEXITCODE)" }

# Step 3/6: Create/update env
Step 3 $TOTAL "Creating/updating env '$EnvName' (can take a few minutes)"

$EnvPrefix = Join-Path $BasePrefix ("envs\{0}" -f $EnvName)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EnvPrefix) | Out-Null

# IMPORTANT: YAML already contains name: rpkm-workshop
# Use -f only; do NOT pass -n (prevents name mismatch issues)
if (Test-Path $EnvPrefix) {
  Write-Host "Environment exists at: $EnvPrefix"
  Run-Exe "mamba env update" $Mamba @("env","update","-f",$EnvYml,"--prune")
} else {
  Write-Host "Environment not found; creating from YAML: $EnvYml"
  Run-Exe "mamba env create" $Mamba @("env","create","-f",$EnvYml)
}

if (!(Test-Path $EnvPrefix)) {
  throw "Environment creation/update did not produce expected prefix: $EnvPrefix"
}

# Step 4/6: Smoke test + triage printout
Step 4 $TOTAL "Smoke test + triage printout"

$SmokePy = Join-Path $TmpRoot "bulk_seq_workshop_smoke_test.py"
$SmokeLines = @(
  'import sys, platform',
  'import numpy, pandas, scipy, sklearn, matplotlib',
  'import anndata, scanpy, umap, pynndescent, statsmodels',
  '',
  'print("SMOKE TEST OK")',
  'print("PY:", sys.version.replace("\n"," "))',
  'print("PLATFORM:", platform.platform())',
  'print("numpy:", numpy.__version__)',
  'print("pandas:", pandas.__version__)',
  'print("scipy:", scipy.__version__)',
  'print("sklearn:", sklearn.__version__)',
  'print("matplotlib:", matplotlib.__version__)',
  'print("scanpy:", scanpy.__version__)',
  'print("anndata:", anndata.__version__)',
  'print("umap:", umap.__version__)',
  'print("pynndescent:", pynndescent.__version__)',
  'print("statsmodels:", statsmodels.__version__)'
)
Set-Content -Path $SmokePy -Value $SmokeLines -Encoding UTF8

Run-Exe "conda run smoke test" $Conda @("run","-n",$EnvName,"python",$SmokePy)

# Step 5/6: Register kernel
Step 5 $TOTAL "Registering Jupyter kernel '$EnvName'"
Run-Exe "ipykernel install" $Conda @("run","-n",$EnvName,"python","-m","ipykernel","install","--user","--name",$EnvName,"--display-name",$EnvName)

# Step 6/6: Launch JupyterLab + notebook
Step 6 $TOTAL "Launching JupyterLab + opening notebooks/workshop.ipynb"
Write-Host ""

Run-Exe "conda run sanity" $Conda @("run","-n",$EnvName,"python","-c","import sys; print('Python OK:', sys.version.split()[0])")

Write-Host "SUCCESS - Environment ready. Launching the notebook now..." -ForegroundColor Green

Set-Location $RepoRoot
Run-Exe "jupyter lab" $Conda @("run","-n",$EnvName,"jupyter","lab",$Notebook)

Write-Host ""
Write-Host "Jupyter exited. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)