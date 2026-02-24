#!/bin/bash
# scripts/launch_mac.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_NAME="rpkm-workshop"
NOTEBOOK="$REPO_ROOT/notebooks/workshop.ipynb"

LOG_DIR="${TMPDIR:-/tmp}/bulk_seq_workshop_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/launch_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

fail() {
  echo ""
  echo "=============================================="
  echo "LAUNCH FAILED"
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

banner "Workshop launch (macOS) — open JupyterLab + notebook"
echo "Repo root: $REPO_ROOT"
echo "Notebook:  $NOTEBOOK"
echo "Log file:  $LOG_FILE"

[[ -f "$NOTEBOOK" ]] || fail "Missing notebook: $NOTEBOOK"

# Find conda
CONDA_BIN=""
if command -v conda >/dev/null 2>&1; then
  CONDA_BIN="$(command -v conda)"
elif [[ -x "$HOME/miniforge3/bin/conda" ]]; then
  CONDA_BIN="$HOME/miniforge3/bin/conda"
else
  fail "conda not found. Please run scripts/setup_mac.command first."
fi

echo "Using conda: $CONDA_BIN"
"$CONDA_BIN" --version

# Ensure conda activation helpers are available in this shell
# shellcheck disable=SC1090
source "$("$CONDA_BIN" info --base)/etc/profile.d/conda.sh"

# Confirm env exists
if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  fail "Environment '$ENV_NAME' not found. Run scripts/setup_mac.command first."
fi

# Quick sanity
conda run -n "$ENV_NAME" python -c "import sys; print('Python OK:', sys.version.split()[0])"

# Launch
cd "$REPO_ROOT"
echo ""
echo "Launching JupyterLab..."
conda run -n "$ENV_NAME" jupyter lab "$NOTEBOOK"