#!/bin/bash
# scripts/launch_mac.command
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$SCRIPT_DIR/launch_mac.sh" || true

"$SCRIPT_DIR/launch_mac.sh"
echo ""
echo "Press Enter to close..."
read