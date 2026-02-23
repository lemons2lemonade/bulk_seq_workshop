#!/bin/bash
set -euo pipefail

# Always run from repo root (one level up from scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_NAME="rpkm-workshop"
NOTEBOOK="$REPO_ROOT/notebooks/workshop.ipynb"

echo "============================================================"
echo "Launching workshop notebook (macOS)"
echo "============================================================"
echo "Repo root: $REPO_ROOT"
echo "Notebook:  $NOTEBOOK"
echo

if [[ ! -f "$NOTEBOOK" ]]; then
  echo "ERROR: Missing notebook: $NOTEBOOK"
  echo "Press Enter to close..."
  read -r
  exit 1
fi

# Find conda
CONDA=""
if command -v conda >/dev/null 2>&1; then
  CONDA="conda"
elif [[ -x "$HOME/miniforge3/bin/conda" ]]; then
  CONDA="$HOME/miniforge3/bin/conda"
elif [[ -x "$HOME/mambaforge/bin/conda" ]]; then
  CONDA="$HOME/mambaforge/bin/conda"
else
  echo "ERROR: conda not found. Please run scripts/setup_mac.command first."
  echo "Press Enter to close..."
  read -r
  exit 1
fi

echo "Using conda: $CONDA"
"$CONDA" --version || true
echo

# Verify env exists
if ! "$CONDA" env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  echo "ERROR: Conda env '$ENV_NAME' not found. Please run scripts/setup_mac.command first."
  echo "Press Enter to close..."
  read -r
  exit 1
fi

cd "$REPO_ROOT"
echo "Launching JupyterLab..."
echo

"$CONDA" run -n "$ENV_NAME" jupyter lab "$NOTEBOOK"

echo
echo "Jupyter exited."
echo "Press Enter to close..."
read -r