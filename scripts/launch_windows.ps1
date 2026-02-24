#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# -----------------------------
# Resolve paths early
# -----------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path

# -----------------------------
# Create dirs we depend on
# -----------------------------
$LogDir = Join-Path $env:TEMP "bulk_seq_workshop_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# -----------------------------
# Always-on logging
# -----------------------------
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

  # Start-Process needs a single argument string; quote args with spaces
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
$EnvName  = "rpkm-workshop"
$Notebook = Join-Path $RepoRoot "notebooks\workshop.ipynb"

Banner "Workshop launch (Windows) - open JupyterLab + notebook"
Write-Host "Repo root: $RepoRoot"
Write-Host "Notebook:  $Notebook"
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion)

if (!(Test-Path $Notebook)) { throw "Missing notebook: $Notebook" }

# -----------------------------
# Find conda
# -----------------------------
$Conda = $null
$MiniforgeConda = "C:\Tools\miniforge3\Scripts\conda.exe"

if (Test-Path $MiniforgeConda) {
  $Conda = $MiniforgeConda
} elseif (Get-Command conda -ErrorAction SilentlyContinue) {
  $Conda = "conda"
} else {
  throw "conda not found. Please run scripts\setup_windows.ps1 first."
}

Write-Host "Using conda: $Conda"
& $Conda --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw "conda version check failed (exit code $LASTEXITCODE)" }

# If using PATH conda, resolve to actual exe for Start-Process
$CondaForStartProcess = $Conda
if ($CondaForStartProcess -eq "conda") {
  $cmd = Get-Command conda -ErrorAction Stop
  $CondaForStartProcess = $cmd.Source
}

# -----------------------------
# Confirm env exists
# -----------------------------
Write-Host ""
Write-Host "Checking environment '$EnvName' exists..." -ForegroundColor Cyan
# This fails fast if the env doesn't exist
Run-Exe -Label "conda run sanity" -Exe $Conda -ArgList @("run","-n",$EnvName,"python","-c","import sys; print('Python OK:', sys.version.split()[0])")

# -----------------------------
# Launch Jupyter + open browser
# -----------------------------
Set-Location $RepoRoot
Start-JupyterAndOpenBrowser -CondaExe $CondaForStartProcess -EnvName $EnvName -RepoRoot $RepoRoot -Notebook $Notebook -LogDir $LogDir

Write-Host ""
Write-Host "Launch complete. Log saved at: $LogFile" -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
Write-Host "Press Enter to close..." -ForegroundColor Yellow
[void](Read-Host)