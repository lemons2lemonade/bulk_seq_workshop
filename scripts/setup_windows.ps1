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
$ToolsRoot    = "C:\Tools"
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

function Start-JupyterAndOpenBrowser([string]$Conda, [string]$EnvName, [string]$RepoRoot, [string]$Notebook, [string]$LogDir) {
  $JupyterLog = Join-Path $LogDir ("jupyter_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
  Write-Host ""
  Write-Host "Jupyter log: $JupyterLog" -ForegroundColor Yellow
  Write-Host "Starting JupyterLab and opening browser..." -ForegroundColor Green

  # Use no-browser so we can explicitly open the URL ourselves (more reliable on Windows).
  # Disable token for workshop ease; change/remove if you want security.
  $args = @(
    "run","-n",$EnvName,"jupyter","lab",
    "--ip=127.0.0.1",
    "--port=8888",
    "--ServerApp.port_retries=50",
    "--no-browser",
    "--NotebookApp.token=",
    "--notebook-dir=$RepoRoot",
    $Notebook
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Conda
  $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
  $psi.WorkingDirectory = $RepoRoot
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $false

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()

  # Capture output briefly to detect the URL if printed; else use default URL
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $url = $null

  while ($sw.Elapsed.TotalSeconds -lt 12 -and -not $p.HasExited) {
    while (-not $p.StandardOutput.EndOfStream) {
      $line = $p.StandardOutput.ReadLine()
      Add-Content -Path $JupyterLog -Value $line
      if (-not $url -and $line -match '(http://127\.0\.0\.1:\d+/\S*)') { $url = $Matches[1] }
    }
    while (-not $p.StandardError.EndOfStream) {
      $eline = $p.StandardError.ReadLine()
      Add-Content -Path $JupyterLog -Value $eline
      if (-not $url -and $eline -match '(http://127\.0\.0\.1:\d+/\S*)') { $url = $Matches[1] }
    }
    Start-Sleep -Milliseconds 200
  }

  if (-not $url) { $url = "http://127.0.0.1:8888/lab" }

  Write-Host ""
  Write-Host "Open this in your browser:" -ForegroundColor Cyan
  Write-Host $url -ForegroundColor Cyan
  Write-Host ""

  try {
    Start-Process $url | Out-Null
    Write-Host "Browser launch attempted." -ForegroundColor Green
  } catch {
    Write-Host "Could not auto-open browser. Please copy/paste the URL above." -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "Jupyter is running. Close your browser when finished." -ForegroundColor Yellow
  Write-Host "You can also close this window (or press Ctrl+C) to stop Jupyter." -ForegroundColor Yellow

  $p.WaitForExit()
  Write-Host ""
  Write-Host "Jupyter exited. Jupyter log: $JupyterLog" -ForegroundColor Yellow
}

# --- Paths & inputs ---
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

$TOTAL = 5

# Step 1/5: Ensure conda (install Miniforge if missing)
Step 1 $TOTAL "Ensuring conda is available (Miniforge if needed)"

$UserProfileMiniforge = Join-Path $env:USERPROFILE "miniforge3"
$UserProfileMambaforge = Join-Path $env:USERPROFILE "mambaforge"
$UserProfileMiniconda  = Join-Path $env:USERPROFILE "miniconda3"
$UserProfileAnaconda   = Join-Path $env:USERPROFILE "anaconda3"

$CondaExe = Join-Path $MiniforgeDir "Scripts\conda.exe"

$Conda = $null
if (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
}
if (-not $Conda -and (Test-Path $CondaExe)) {
  $Conda = $CondaExe
}

if (-not $Conda) {
  if ((Test-Path $MiniforgeDir) -and !(Test-Path $CondaExe)) {
    Write-Host "Detected partial Miniforge at target location (missing conda.exe)." -ForegroundColor Yellow
    Quarantine-Dir $MiniforgeDir
  }

  foreach ($p in @($UserProfileMiniforge, $UserProfileMambaforge, $UserProfileMiniconda, $UserProfileAnaconda)) {
    if (Test-Path $p) {
      Write-Host "Detected old conda install in user profile: $p" -ForegroundColor Yellow
      Quarantine-Dir $p
    }
  }

  Write-Host "conda not found - installing Miniforge (no admin required)"
  Write-Host "Miniforge target: $MiniforgeDir"

  if ($MiniforgeDir -match "\s") { throw "Internal error: MiniforgeDir contains spaces: $MiniforgeDir" }

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

# Step 2/5: Create/update env
Step 2 $TOTAL "Creating/updating env '$EnvName' (can take a few minutes)"
$BasePrefix = & $Conda info --base
$EnvPrefix  = Join-Path $BasePrefix ("envs\{0}" -f $EnvName)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EnvPrefix) | Out-Null

if (Test-Path $EnvPrefix) {
  Write-Host "Environment exists at: $EnvPrefix"
  Run-Exe "conda env update" $Conda @("env","update","-n",$EnvName,"-f",$EnvYml,"--prune")
} else {
  Write-Host "Environment not found; creating from YAML: $EnvYml"
  Run-Exe "conda env create" $Conda @("env","create","-f",$EnvYml)
}

Run-Exe "conda run sanity" $Conda @("run","-n",$EnvName,"python","-c","import sys; print('Python OK:', sys.version.split()[0])")

# Step 3/5: Smoke test + triage printout
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
Run-Exe "conda run smoke test" $Conda @("run","-n",$EnvName,"python",$SmokePy)

# Step 4/5: Register kernel
Step 4 $TOTAL "Registering Jupyter kernel '$EnvName'"
Run-Exe "ipykernel install" $Conda @("run","-n",$EnvName,"python","-m","ipykernel","install","--user","--name",$EnvName,"--display-name",$EnvName)

# Step 5/5: Launch + auto-open in browser
Step 5 $TOTAL "Launching JupyterLab + opening notebooks/workshop.ipynb"
Write-Host ""
Write-Host "SUCCESS - Environment ready. Launching the notebook now..." -ForegroundColor Green

Set-Location $RepoRoot
Start-JupyterAndOpenBrowser -Conda $Conda -EnvName $EnvName -RepoRoot $RepoRoot -Notebook $Notebook -LogDir $LogDir

Write-Host ""
Write-Host "Setup complete. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)