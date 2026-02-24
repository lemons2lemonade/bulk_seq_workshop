#!/bin/bash
set -euo pipefail

# -----------------------------
# Paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_YML="$REPO_ROOT/environment.workshop.yml"
NOTEBOOK="$REPO_ROOT/notebooks/workshop.ipynb"
ENV_NAME="rpkm-workshop"

# -----------------------------
# Logging
# -----------------------------
LOG_DIR="${TMPDIR:-/tmp}/bulk_seq_workshop_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

fail() {
  echo ""
  echo "=============================================="
  echo "SETUP FAILED"
  echo "=============================================="
  echo "$1"
  echo ""
  echo "Log saved at: $LOG_FILE"
  exit 1
}

banner() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

step() {
  echo ""
  echo "[Step $1/$2] $3"
  echo "------------------------------------------------------------"
}

# -----------------------------
# Validate inputs
# -----------------------------
[[ -f "$ENV_YML" ]] || fail "Missing environment file: $ENV_YML"
[[ -f "$NOTEBOOK" ]] || fail "Missing notebook: $NOTEBOOK"

banner "Workshop setup (macOS) — automatic install + env + Jupyter"
echo "Repo root: $REPO_ROOT"
echo "Env file:  $ENV_YML"
echo "Notebook:  $NOTEBOOK"
echo "Log file:  $LOG_FILE"

TOTAL=5

# -----------------------------
# Step 1/5: Ensure conda (Miniforge) available
# -----------------------------
step 1 $TOTAL "Ensuring conda is available (Miniforge if needed)"

# Prefer existing conda if present
CONDA_BIN=""
if command -v conda >/dev/null 2>&1; then
  CONDA_BIN="$(command -v conda)"
else
  # Install Miniforge to ~/miniforge3 (no admin)
  MINIFORGE_DIR="$HOME/miniforge3"
  CONDA_CAND="$MINIFORGE_DIR/bin/conda"

  if [[ -x "$CONDA_CAND" ]]; then
    CONDA_BIN="$CONDA_CAND"
  else
    echo "conda not found — installing Miniforge (no admin required)"
    echo "Target: $MINIFORGE_DIR"

    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
      MF_PKG="Miniforge3-MacOSX-arm64.sh"
    else
      MF_PKG="Miniforge3-MacOSX-x86_64.sh"
    fi
    URL="https://github.com/conda-forge/miniforge/releases/latest/download/$MF_PKG"
    INSTALLER="${TMPDIR:-/tmp}/$MF_PKG"

    echo "Downloading: $URL"
    curl -L --fail "$URL" -o "$INSTALLER"

    echo "Running installer..."
    bash "$INSTALLER" -b -p "$MINIFORGE_DIR"

    CONDA_BIN="$CONDA_CAND"
    [[ -x "$CONDA_BIN" ]] || fail "Miniforge installed but conda not found at: $CONDA_BIN"
  fi
fi

echo "Using conda: $CONDA_BIN"
"$CONDA_BIN" --version

# Ensure conda’s base scripts available in this shell session
# shellcheck disable=SC1090
source "$("$CONDA_BIN" info --base)/etc/profile.d/conda.sh"

# -----------------------------
# Step 2/5: Create/update env
# -----------------------------
step 2 $TOTAL "Creating/updating env '$ENV_NAME' (can take a few minutes)"

if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  echo "Environment exists; updating from YAML..."
  conda env update -n "$ENV_NAME" -f "$ENV_YML" --prune
else
  echo "Environment not found; creating from YAML..."
  conda env create -f "$ENV_YML"
fi

# Sanity
conda run -n "$ENV_NAME" python -c "import sys; print('Python OK:', sys.version.split()[0])"

# -----------------------------
# Step 3/5: Smoke test
# -----------------------------
step 3 $TOTAL "Smoke test + triage printout"

SMOKE_PY="${TMPDIR:-/tmp}/bulk_seq_workshop_smoke_test.py"
cat > "$SMOKE_PY" <<'PY'
import sys, platform
import numpy, pandas, scipy, sklearn, matplotlib
import anndata, scanpy, umap, pynndescent, statsmodels

print("SMOKE TEST OK")
print("PY:", sys.version.replace("\n"," "))
print("PLATFORM:", platform.platform())
print("numpy:", numpy.__version__)
print("pandas:", pandas.__version__)
print("scipy:", scipy.__version__)
print("sklearn:", sklearn.__version__)
print("matplotlib:", matplotlib.__version__)
print("scanpy:", scanpy.__version__)
print("anndata:", anndata.__version__)
print("umap:", umap.__version__)
print("pynndescent:", pynndescent.__version__)
print("statsmodels:", statsmodels.__version__)
PY

conda run -n "$ENV_NAME" python "$SMOKE_PY"

# -----------------------------
# Step 4/5: Register kernel
# -----------------------------
step 4 $TOTAL "Registering Jupyter kernel '$ENV_NAME'"

conda run -n "$ENV_NAME" python -m ipykernel install --user --name "$ENV_NAME" --display-name "$ENV_NAME"

# -----------------------------
# Step 5/5: Launch Jupyter + open notebook
# -----------------------------
step 5 $TOTAL "Launching JupyterLab + opening notebooks/workshop.ipynb"

echo ""
echo "SUCCESS ✅ Environment ready. Launching JupyterLab..."
echo "Log: $LOG_FILE"
echo ""

# Start Jupyter in foreground (Terminal stays open) + open browser
cd "$REPO_ROOT"
conda run -n "$ENV_NAME" jupyter lab "$NOTEBOOK"