#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Logging (always on)
# ----------------------------
$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("setup_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "Logging to: $LogFile"

function Banner([string]$msg) {
  Write-Host ""
  Write-Host "============================================================"
  Write-Host $msg
  Write-Host "============================================================"
}

function Step([int]$i, [int]$n, [string]$msg) {
  Write-Host ""
  Write-Host ("[Step {0}/{1}] {2}" -f $i, $n, $msg)
  Write-Host "------------------------------------------------------------"
}

function Success([string]$msg) {
  Write-Host ""
  Write-Host "============================================================" -ForegroundColor Green
  Write-Host ("SUCCESS ✅  {0}" -f $msg) -ForegroundColor Green
  Write-Host "============================================================" -ForegroundColor Green
}

function Fail([string]$msg) {
  throw $msg
}

function Diagnostics([string]$RepoRoot, [string]$EnvYml, [string]$Notebook) {
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

  # DNS sanity check (GitHub reachability)
  try {
    $null = Resolve-DnsName "github.com" -ErrorAction Stop
    Write-Host "Network/DNS: OK (github.com resolves)"
  } catch {
    Fail "Network/DNS check failed: cannot resolve github.com. Are you offline or behind restrictive DNS?"
  }
}

try {
  Banner "Workshop setup (Windows) — automatic install + env + Jupyter"

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

    # Run silent installer; /D must be last and no quotes around it
    $args = @("/S", "/D=$MiniforgeDir")
    $p = Start-Process -FilePath $Installer -ArgumentList $args -Wait -PassThru

    if ($p.ExitCode -ne 0) { Fail "Miniforge installer failed with exit code $($p.ExitCode)" }
    if (!(Test-Path $CondaExe)) { Fail "Miniforge install completed but conda not found at $CondaExe" }

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
    $Candidate  = Join-Path $BasePrefix "Scripts\mamba.exe"

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
  # Step 3/6 — Create/update environment
  # ----------------------------
  Step 3 $TOTAL_STEPS "Creating/updating env '$EnvName' from environment.workshop.yml (can take a few minutes)"
  & $MambaExe env update -n $EnvName -f $EnvYml --prune | Out-Host

  # ----------------------------
  # Step 4/6 — Smoke test + triage printout
  # ----------------------------
  Step 4 $TOTAL_STEPS "Smoke test + triage printout"

  $Py = @(
    "import sys, platform",
    "import numpy, pandas, scipy, sklearn, matplotlib",
    "print('SMOKE TEST OK')",
    "print('PY:', sys.version.replace('\n',' '))",
    "print('PLATFORM:', platform.platform())",
    "print('numpy:', numpy.__version__)",
    "print('pandas:', pandas.__version__)",
    "print('scipy:', scipy.__version__)",
    "print('sklearn:', sklearn.__version__)",
    "print('matplotlib:', matplotlib.__version__)"
  ) -join "; "

  & $CondaCmd run -n $EnvName python -c $Py | Out-Host

  # ----------------------------
  # Step 5/6 — Register Jupyter kernel
  # ----------------------------
  Step 5 $TOTAL_STEPS "Registering Jupyter kernel '$KernelDisp'"
  & $CondaCmd run -n $EnvName python -m ipykernel install --user --name $KernelName --display-name $KernelDisp | Out-Host

  # ----------------------------
  # Step 6/6 — Launch JupyterLab + open notebook
  # ----------------------------
  Step 6 $TOTAL_STEPS "Launching JupyterLab + opening notebooks/workshop.ipynb"
  Success "Environment ready. Launching the notebook now…"

  Set-Location $RepoRoot
  & $CondaCmd run -n $EnvName jupyter lab $Notebook

  # If Jupyter exits, we still keep the window open so people can see logs.
  Write-Host ""
  Write-Host "Jupyter exited. Log saved at: $LogFile" -ForegroundColor Yellow
  Write-Host "Press Enter to close..." -ForegroundColor Yellow
  [void] (Read-Host)

} catch {
  Write-Host ""
  Write-Host "============================================================" -ForegroundColor Red
  Write-Host "SETUP FAILED ❌" -ForegroundColor Red
  Write-Host "============================================================" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host ("Full log saved at: {0}" -f $LogFile) -ForegroundColor Yellow
  Write-Host "Press Enter to close..." -ForegroundColor Yellow
  try { Stop-Transcript | Out-Null } catch {}
  [void] (Read-Host)
  exit 1
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}