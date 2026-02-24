#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# -----------------------------
# Resolve paths early
# -----------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

# -----------------------------
# Create all directories we depend on
# -----------------------------
$TmpRoot = Join-Path $env:TEMP "bulk_seq_workshop_tmp"
New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null

$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Workshop-safe, no-space install root for Miniforge
$ToolsRoot    = "C:\Tools"
$MiniforgeDir = Join-Path $ToolsRoot "miniforge3"
New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null

# -----------------------------
# Always-on logging
# -----------------------------
$LogFile = Join-Path $LogDir ("setup_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "Logging to: $LogFile"

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

# -----------------------------
# Helpers (avoid $Args/$args footguns)
# -----------------------------
function Run-Exe {
  param(
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string]$Exe,
    [Parameter(Mandatory=$true)][string[]]$ArgList
  )
  Write-Host ">> $Label"
  & $Exe @ArgList | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed (exit code $LASTEXITCODE)"
  }
}

function Ensure-ParentDir([string]$Path) {
  $parent = Split-Path -Parent $Path
  if ($parent -and !(Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
}

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

function Wait-Port {
  param(
    [Parameter(Mandatory=$true)][string]$Host,
    [Parameter(Mandatory=$true)][int]$Port,
    [Parameter(Mandatory=$true)][int]$Seconds
  )
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $client = New-Object System.Net.Sockets.TcpClient
      $iar = $client.BeginConnect($Host, $Port, $null, $null)
      if ($iar.AsyncWaitHandle.WaitOne(250)) {
        $client.EndConnect($iar)
        $client.Close()
        return $true
      }
      $client.Close()
    } catch { }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

function Start-JupyterAndOpenBrowser {
  param(
    [Parameter(Mandatory=$true)][string]$CondaExe,
    [Parameter(Mandatory=$true)][string]$EnvName,
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$Notebook,
    [Parameter(Mandatory=$true)][string]$LogDir
  )

  $JupyterOut = Join-Path $LogDir ("jupyter_{0}.out.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
  $JupyterErr = Join-Path $LogDir ("jupyter_{0}.err.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

  $port = 8888
  $url  = "http://127.0.0.1:$port/lab"

  Write-Host ""
  Write-Host "Jupyter stdout: $JupyterOut" -ForegroundColor Yellow
  Write-Host "Jupyter stderr: $JupyterErr" -ForegroundColor Yellow
  Write-Host "Starting JupyterLab..." -ForegroundColor Green

  # IMPORTANT: pass tokens as separate args (no quoting games inside strings)
  $argList = @(
    "run","-n",$EnvName,
    "jupyter","lab",
    "--ip=127.0.0.1",
    "--port=$port",
    "--ServerApp.port_retries=50",
    "--no-browser",
    "--ServerApp.token=",
    "--notebook-dir=$RepoRoot",
    $Notebook
  )

  # Start-Process takes a single string ArgumentList, so we quote args with spaces here.
  $argString = ($argList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "

  $p = Start-Process -FilePath $CondaExe `
    -ArgumentList $argString `
    -WorkingDirectory $RepoRoot `
    -RedirectStandardOutput $JupyterOut `
    -RedirectStandardError $JupyterErr `
    -PassThru

  Write-Host "Waiting for Jupyter on $url ..." -ForegroundColor Cyan
  if (-not (Wait-Port -Host "127.0.0.1" -Port $port -Seconds 60)) {
    throw "Jupyter did not become reachable on $url within 60s. Check $JupyterErr"
  }

  Write-Host "Opening browser: $url" -ForegroundColor Green
  try { Start-Process $url | Out-Null } catch { Write-Host "Auto-open failed. Copy/paste: $url" -ForegroundColor Yellow }

  Write-Host ""
  Write-Host "Jupyter is running. Close this window (or press Ctrl+C) to stop it." -ForegroundColor Yellow
  $p.WaitForExit()
  Write-Host "Jupyter exited." -ForegroundColor Yellow
}

# -----------------------------
# Inputs
# -----------------------------
$EnvYml   = Join-Path $RepoRoot "environment.workshop.yml"
$Notebook = Join-Path $RepoRoot "notebooks\workshop.ipynb"
$EnvName  = "rpkm-workshop"

if (!(Test-Path $EnvYml))   { throw "Missing environment file: $EnvYml" }
if (!(Test-Path $Notebook)) { throw "Missing notebook: $Notebook" }

Banner "Workshop setup (Windows) - automatic install + env + Jupyter"
Write-Host "Repo root: $RepoRoot"
Write-Host "Env file:  $EnvYml"
Write-Host "Notebook:  $Notebook"
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)

# Guard: do not run as Administrator (workshop installs per-user)
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) { throw "Please do NOT run as Administrator. Close this window and run setup normally (per-user install)." }

# DNS sanity check
try {
  $null = Resolve-DnsName "github.com" -ErrorAction Stop
  Write-Host "Network/DNS: OK (github.com resolves)"
} catch {
  throw "Network/DNS check failed: cannot resolve github.com."
}

$TOTAL = 5

# -----------------------------
# Step 1/5: Ensure conda exists (install Miniforge if missing)
# -----------------------------
Step 1 $TOTAL "Ensuring conda is available (Miniforge if needed)"

$CondaExe = Join-Path $MiniforgeDir "Scripts\conda.exe"
$Conda = $null

# Prefer our no-space install if present
if (Test-Path $CondaExe) {
  $Conda = $CondaExe
} elseif (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
}

if (-not $Conda) {
  # Quarantine common broken/spacey installs from earlier attempts
  foreach ($p in @(
    (Join-Path $env:USERPROFILE "miniforge3"),
    (Join-Path $env:USERPROFILE "mambaforge"),
    (Join-Path $env:USERPROFILE "miniconda3"),
    (Join-Path $env:USERPROFILE "anaconda3")
  )) {
    if (Test-Path $p) { Quarantine-Dir $p }
  }

  # If target exists but missing conda.exe, quarantine partial target
  if ((Test-Path $MiniforgeDir) -and !(Test-Path $CondaExe)) {
    Quarantine-Dir $MiniforgeDir
  }

  Write-Host "conda not found - installing Miniforge (no admin required)"
  Write-Host "Miniforge target: $MiniforgeDir"

  if ($MiniforgeDir -match "\s") { throw "Internal error: MiniforgeDir contains spaces: $MiniforgeDir" }

  $Installer = Join-Path $TmpRoot "Miniforge3-Windows-x86_64.exe"
  $Url = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"

  if (Test-Path $Installer) {
    $len = (Get-Item $Installer).Length
    if ($len -lt 10MB) { Remove-Item -Force $Installer }
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

# -----------------------------
# Step 2/5: Create/update env
# -----------------------------
Step 2 $TOTAL "Creating/updating env '$EnvName' (can take a few minutes)"

# Use conda info --base to locate env prefix deterministically
$BasePrefix = & $Conda info --base
if ($LASTEXITCODE -ne 0 -or -not $BasePrefix) { throw "Failed to determine conda base prefix." }

$EnvPrefix = Join-Path $BasePrefix ("envs\{0}" -f $EnvName)

if (Test-Path $EnvPrefix) {
  Write-Host "Environment exists at: $EnvPrefix"
  Run-Exe -Label "conda env update" -Exe $Conda -ArgList @("env","update","-n",$EnvName,"-f",$EnvYml,"--prune")
} else {
  Write-Host "Environment not found; creating from YAML: $EnvYml"
  Run-Exe -Label "conda env create" -Exe $Conda -ArgList @("env","create","-f",$EnvYml)
}

Run-Exe -Label "conda run sanity" -Exe $Conda -ArgList @("run","-n",$EnvName,"python","-c","import sys; print('Python OK:', sys.version.split()[0])")

# -----------------------------
# Step 3/5: Smoke test
# -----------------------------
Step 3 $TOTAL "Smoke test + triage printout"

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
Run-Exe -Label "conda run smoke test" -Exe $Conda -ArgList @("run","-n",$EnvName,"python",$SmokePy)

# -----------------------------
# Step 4/5: Register kernel
# -----------------------------
Step 4 $TOTAL "Registering Jupyter kernel '$EnvName'"
Run-Exe -Label "ipykernel install" -Exe $Conda -ArgList @("run","-n",$EnvName,"python","-m","ipykernel","install","--user","--name",$EnvName,"--display-name",$EnvName)

# -----------------------------
# Step 5/5: Launch + open browser
# -----------------------------
Step 5 $TOTAL "Launching JupyterLab + opening notebooks/workshop.ipynb"
Write-Host ""
Write-Host "SUCCESS - Environment ready. Launching the notebook now..." -ForegroundColor Green

Set-Location $RepoRoot

# IMPORTANT: if we used "conda" from PATH, we still need an actual exe path for Start-Process
$CondaForStartProcess = $Conda
if ($CondaForStartProcess -eq "conda") {
  $cmd = Get-Command conda -ErrorAction Stop
  $CondaForStartProcess = $cmd.Source
}

Start-JupyterAndOpenBrowser -CondaExe $CondaForStartProcess -EnvName $EnvName -RepoRoot $RepoRoot -Notebook $Notebook -LogDir $LogDir

Write-Host ""
Write-Host "Setup complete. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)