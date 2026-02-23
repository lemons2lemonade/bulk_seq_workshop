#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Banner($msg) {
  Write-Host ""
  Write-Host "============================================================"
  Write-Host $msg
  Write-Host "============================================================"
}

function Step($i, $n, $msg) {
  Write-Host ""
  Write-Host ("[Step {0}/{1}] {2}" -f $i, $n, $msg)
  Write-Host "------------------------------------------------------------"
}

function Success($msg) {
  Write-Host ""
  Write-Host "============================================================" -ForegroundColor Green
  Write-Host ("SUCCESS ✅  {0}" -f $msg) -ForegroundColor Green
  Write-Host "============================================================" -ForegroundColor Green
}

function Fail($msg) {
  Write-Host ""
  Write-Host "============================================================" -ForegroundColor Red
  Write-Host ("ERROR ❌  {0}" -f $msg) -ForegroundColor Red
  Write-Host "============================================================" -ForegroundColor Red
  exit 1
}

function Diagnostics($RepoRoot, $EnvYml, $Notebook) {
  Banner "Diagnostics (Windows)"
  try {
    $os = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption
  } catch {
    $os = "Windows (unable to query Win32_OperatingSystem)"
  }
  Write-Host ("OS: {0}" -f $os)
  Write-Host ("Version: {0}" -f ([System.Environment]::OSVersion.VersionString))
  Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)
  Write-Host ("User: {0}" -f $env:USERNAME)
  Write-Host ("Repo root: {0}" -f $RepoRoot)
  Write-Host ("Env file:  {0}" -f $EnvYml)
  Write-Host ("Notebook:  {0}" -f $Notebook)

  # Network/DNS sanity check (GitHub reachability)
  try {
    $null = Resolve-DnsName "github.com" -ErrorAction Stop
    Write-Host "Network/DNS: OK (github.com resolves)"
  } catch {
    Fail "Network/DNS check failed: cannot resolve github.com. Are you offline or behind restrictive DNS?"
  }
}

# ----------------------------
# Paths / constants
# ----------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

$EnvYml      = Join-Path $RepoRoot "environment.workshop.yml"
$EnvName     = "rpkm-workshop"
$KernelName  = "rpkm-workshop"
$KernelDisp  = "rpkm-workshop"
$NotebookRel = "notebooks\workshop.ipynb"
$Notebook    = Join-Path $RepoRoot $NotebookRel

$MiniforgeDir = Join-Path $env:USERPROFILE "miniforge3"
$CondaExe     = Join-Path $MiniforgeDir "Scripts\conda.exe"

if (!(Test-Path $EnvYml))   { Fail "Missing environment file: $EnvYml" }
if (!(Test-Path $Notebook)) { Fail "Missing notebook: $Notebook" }

Banner "Workshop setup (Windows) — automatic install + env + Jupyter"

Diagnostics $RepoRoot $EnvYml $Notebook

$TOTAL_STEPS = 6

# ----------------------------
# Step 1/6 — Ensure conda exists (install Miniforge if needed)
# ----------------------------
Step 1 $TOTAL_STEPS "Ensuring conda is available (Miniforge if needed)"
$CondaCmd = $null
if (Get-Command conda -ErrorAction SilentlyContinue) {
  $CondaCmd = "conda"
} elseif (Test-Path $CondaExe) {
  $CondaCmd = $CondaExe
} else {
  Write-Host "conda not found — installing Miniforge (no admin required)"
  $Installer = Join-Path $env:TEMP "Miniforge3-Windows-x86_64.exe"
  $Url = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"

  Invoke-WebRequest -Uri $Url -OutFile $Installer
  Start-Process -FilePath $Installer -ArgumentList "/S", "/D=$MiniforgeDir" -Wait

  if (!(Test-Path $CondaExe)) { Fail "Miniforge install failed; conda not found at $CondaExe" }
  $CondaCmd = $CondaExe
}
Write-Host "Using conda: $CondaCmd"
Write-Host "conda version:" (& $CondaCmd --version)

# ----------------------------
# Step 2/6 — Ensure mamba exists (install only if missing)
# ----------------------------
Step 2 $TOTAL_STEPS "Ensuring mamba is available (install only if missing)"
$MambaExe = $null

if (Get-Command mamba -ErrorAction SilentlyContinue) {
  $MambaExe = "mamba"
} else {
  $BasePrefix = & $CondaCmd info --base
  $Candidate = Join-Path $BasePrefix "Scripts\mamba.exe"

  if (Test-Path $Candidate) {
    $MambaExe = $Candidate
  } else {
    Write-Host "mamba not found — installing into base env"
    & $CondaCmd install -n base -c conda-forge -y mamba | Out-Host

    if (Test-Path $Candidate) {
      $MambaExe = $Candidate
    } elseif (Get-Command mamba -ErrorAction SilentlyContinue) {
      $MambaExe = "mamba"
    } else {
      Fail "mamba installation failed"
    }
  }
}

Write-Host "Using mamba: $MambaExe"
Write-Host "mamba version:" (& $MambaExe --version)

# ----------------------------
# Step 3/6 — Create/update environment from environment.workshop.yml
# ----------------------------
Step 3 $TOTAL_STEPS "Creating/updating env '$EnvName' (this can take a few minutes)"
& $MambaExe env update -n $EnvName -f $EnvYml --prune | Out-Host

# ----------------------------
# Step 4/6 — Smoke test + triage printout (fail-fast)
# ----------------------------
Step 4 $TOTAL_STEPS "Smoke test + triage printout"
& $CondaCmd run -n $EnvName python -c @"
import sys, platform
import numpy, pandas, scipy, sklearn, matplotlib
print("SMOKE TEST OK")
print("PY:", sys.version.replace("\n"," "))
print("PLATFORM:", platform.platform())
print("numpy:", numpy.__version__)
print("pandas:", pandas.__version__)
print("scipy:", scipy.__version__)
print("sklearn:", sklearn.__version__)
print("matplotlib:", matplotlib.__version__)
"@ | Out-Host

# ----------------------------
# Step 5/6 — Register Jupyter kernel
# ----------------------------
Step 5 $TOTAL_STEPS "Registering Jupyter kernel '$KernelDisp'"
& $CondaCmd run -n $EnvName python -m ipykernel install --user --name $KernelName --display-name $KernelDisp | Out-Host

# ----------------------------
# Step 6/6 — Launch JupyterLab and open notebook
# ----------------------------
Step 6 $TOTAL_STEPS "Launching JupyterLab + opening notebooks/workshop.ipynb"
Success "Environment ready. Launching the notebook now…"

Set-Location $RepoRoot
& $CondaCmd run -n $EnvName jupyter lab $Notebook