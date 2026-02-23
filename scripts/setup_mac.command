#!/usr/bin/env bash
set -euo pipefail

banner() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

step() {
  local i="$1"; local n="$2"; local msg="$3"
  echo ""
  echo "[Step ${i}/${n}] ${msg}"
  echo "------------------------------------------------------------"
}

success() {
  echo ""
  echo "============================================================"
  echo "SUCCESS ✅  $1"
  echo "============================================================"
}

fail() {
  echo ""
  echo "============================================================" >&2
  echo "ERROR ❌  $1" >&2
  echo "============================================================" >&2
  exit 1
}

diagnostics() {
  local repo_root="$1"
  local env_yml="$2"
  local notebook="$3"

  banner "Diagnostics (macOS)"
  echo "OS: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "Arch: $(uname -m)"
  echo "Shell: ${SHELL:-unknown}"
  echo "User: $(id -un)"
  echo "Repo root: $repo_root"
  echo "Env file:  $env_yml"
  echo "Notebook:  $notebook"

  # Network/DNS sanity check (GitHub reachability)
  if ! host github.com >/dev/null 2>&1; then
    fail "Network/DNS check failed: cannot resolve github.com. Are you offline or behind restrictive DNS?"
  fi
  echo "Network/DNS: OK (github.com resolves)"
}

banner "Workshop setup (macOS) — automatic install + env + Jupyter"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_YML="$REPO_ROOT/environment.workshop.yml"
ENV_NAME="rpkm-workshop"
KERNEL_NAME="rpkm-workshop"
KERNEL_DISPLAY="rpkm-workshop"
NOTEBOOK="$REPO_ROOT/notebooks/workshop.ipynb"

[[ -f "$ENV_YML" ]] || fail "Missing environment file: $ENV_YML"
[[ -f "$NOTEBOOK" ]] || fail "Missing notebook: $NOTEBOOK"

diagnostics "$REPO_ROOT" "$ENV_YML" "$NOTEBOOK"

TOTAL_STEPS=6

# ----------------------------
# Step 1/6 — Ensure conda exists (install Miniforge if needed)
# ----------------------------
step 1 "$TOTAL_STEPS" "Ensuring conda is available (Miniforge if needed)"

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  MINIFORGE_SH="Miniforge3-MacOSX-arm64.sh"
else
  MINIFORGE_SH="Miniforge3-MacOSX-x86_64.sh"
fi

MINIFORGE_DIR="$HOME/miniforge3"
CONDA_BIN="$MINIFORGE_DIR/bin/conda"

if command -v conda >/dev/null 2>&1; then
  CONDA="conda"
elif [[ -x "$CONDA_BIN" ]]; then
  CONDA="$CONDA_BIN"
else
  echo "conda not found — installing Miniforge (no admin required)"
  URL="https://github.com/conda-forge/miniforge/releases/latest/download/${MINIFORGE_SH}"
  INSTALLER="$REPO_ROOT/.miniforge_installer.sh"
  curl -L "$URL" -o "$INSTALLER"
  bash "$INSTALLER" -b -p "$MINIFORGE_DIR"
  rm -f "$INSTALLER"
  [[ -x "$CONDA_BIN" ]] || fail "Miniforge install failed; conda not found at $CONDA_BIN"
  CONDA="$CONDA_BIN"
fi

echo "Using conda: $CONDA"
echo "conda version: $("$CONDA" --version)"

# ----------------------------
# Step 2/6 — Ensure mamba exists (install only if missing)
# ----------------------------
step 2 "$TOTAL_STEPS" "Ensuring mamba is available (install only if missing)"

if command -v mamba >/dev/null 2>&1; then
  MAMBA="mamba"
else
  BASE_PREFIX="$("$CONDA" info --base)"
  CANDIDATE="$BASE_PREFIX/bin/mamba"

  if [[ -x "$CANDIDATE" ]]; then
    MAMBA="$CANDIDATE"
  else
    echo "mamba not found — installing into base env"
    "$CONDA" install -n base -c conda-forge -y mamba

    if [[ -x "$CANDIDATE" ]]; then
      MAMBA="$CANDIDATE"
    elif command -v mamba >/dev/null 2>&1; then
      MAMBA="mamba"
    else
      fail "mamba installation failed"
    fi
  fi
fi

echo "Using mamba: $MAMBA"
echo "mamba version: $("$MAMBA" --version)"

# ----------------------------
# Step 3/6 — Create/update environment
# ----------------------------
step 3 "$TOTAL_STEPS" "Creating/updating env '$ENV_NAME' (this can take a few minutes)"
"$MAMBA" env update -n "$ENV_NAME" -f "$ENV_YML" --prune

# ----------------------------
# Step 4/6 — Smoke test + triage printout (fail-fast)
# ----------------------------
step 4 "$TOTAL_STEPS" "Smoke test + triage printout"
"$CONDA" run -n "$ENV_NAME" python - <<'PY'
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
PY

# ----------------------------
# Step 5/6 — Register kernel
# ----------------------------
step 5 "$TOTAL_STEPS" "Registering Jupyter kernel '$KERNEL_DISPLAY'"
"$CONDA" run -n "$ENV_NAME" python -m ipykernel install --user --name "$KERNEL_NAME" --display-name "$KERNEL_DISPLAY"

# ----------------------------
# Step 6/6 — Launch JupyterLab and open notebook
# ----------------------------
step 6 "$TOTAL_STEPS" "Launching JupyterLab + opening notebooks/workshop.ipynb"
success "Environment ready. Launching the notebook now…"

cd "$REPO_ROOT"
"$CONDA" run -n "$ENV_NAME" jupyter lab "$NOTEBOOK"