#!/bin/bash
# Double-clickable wrapper for macOS Finder
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$SCRIPT_DIR/setup_mac.sh" || true

# Run in Terminal and keep it open by default when double-clicked
"$SCRIPT_DIR/setup_mac.sh"
echo ""
echo "Press Enter to close..."
read