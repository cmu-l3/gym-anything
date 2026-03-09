#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Audit Technical Markers Result ==="

WORKSPACE="/home/ga/workspace/inventory-api"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

# Wait for files to be written
sleep 2

# Export the audit document
if [ -f "$WORKSPACE/TECHNICAL_DEBT.md" ]; then
    cp "$WORKSPACE/TECHNICAL_DEBT.md" /tmp/TECHNICAL_DEBT.md
    echo "✅ Exported TECHNICAL_DEBT.md"
else
    echo "" > /tmp/TECHNICAL_DEBT.md
    echo "⚠️ TECHNICAL_DEBT.md not found"
fi

# Export modified source files for verification
cp "$WORKSPACE/src/database.py" /tmp/database.py 2>/dev/null || echo "" > /tmp/database.py
cp "$WORKSPACE/src/api.py" /tmp/api.py 2>/dev/null || echo "" > /tmp/api.py
cp "$WORKSPACE/src/validation.py" /tmp/validation.py 2>/dev/null || echo "" > /tmp/validation.py
cp "$WORKSPACE/src/utils.py" /tmp/utils.py 2>/dev/null || echo "" > /tmp/utils.py

echo "✅ Export complete"
echo "Exported files:"
echo "  - /tmp/TECHNICAL_DEBT.md"
echo "  - /tmp/database.py"
echo "  - /tmp/api.py"
echo "  - /tmp/validation.py"
echo "  - /tmp/utils.py"