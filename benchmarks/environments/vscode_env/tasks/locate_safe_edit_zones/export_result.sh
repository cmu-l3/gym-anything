#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Locate Safe Edit Zones Result ==="

WORKSPACE="/home/ga/workspace/api-client-project"

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not trigger save; continuing"
}

# Wait for guide file to be written
wait_for_file "$WORKSPACE/SAFE_EDIT_GUIDE.md" 3 || echo "⚠️ SAFE_EDIT_GUIDE.md not found yet"

# Export the guide to /tmp for verifier
if [ -f "$WORKSPACE/SAFE_EDIT_GUIDE.md" ]; then
    cp "$WORKSPACE/SAFE_EDIT_GUIDE.md" /tmp/SAFE_EDIT_GUIDE.md
    echo "✅ Exported SAFE_EDIT_GUIDE.md to /tmp"
else
    echo "⚠️ SAFE_EDIT_GUIDE.md not found in workspace"
    echo "" > /tmp/SAFE_EDIT_GUIDE.md
fi

# Also export project structure for debugging
ls -la "$WORKSPACE" > /tmp/workspace_structure.txt 2>&1 || true
find "$WORKSPACE" -type f -name "*.ts" -o -name "*.yml" -o -name "*.md" > /tmp/workspace_files.txt 2>&1 || true

echo "✅ Export complete"
echo "Expected file: $WORKSPACE/SAFE_EDIT_GUIDE.md"