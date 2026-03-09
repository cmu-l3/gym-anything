#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bundle Analysis Result ==="

WORKSPACE_DIR="/home/ga/workspace/react-app"

# Save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save in VSCode; continuing"
}

# Give time for file writes to complete
sleep 2

# Export package.json for verification
if [ -f "$WORKSPACE_DIR/package.json" ]; then
    echo "Copying package.json..."
    cp "$WORKSPACE_DIR/package.json" /tmp/package.json 2>&1 || echo "{}" > /tmp/package.json
else
    echo "{}" > /tmp/package.json
fi

# Export BUNDLE_ANALYSIS.md if it exists
if [ -f "$WORKSPACE_DIR/BUNDLE_ANALYSIS.md" ]; then
    echo "Copying BUNDLE_ANALYSIS.md..."
    cp "$WORKSPACE_DIR/BUNDLE_ANALYSIS.md" /tmp/BUNDLE_ANALYSIS.md 2>&1
    echo "✅ Bundle analysis report found"
else
    echo "" > /tmp/BUNDLE_ANALYSIS.md
    echo "⚠️ BUNDLE_ANALYSIS.md not found"
fi

# Export list of files in workspace for debugging
ls -la "$WORKSPACE_DIR/" > /tmp/workspace_files.txt 2>&1 || echo "" > /tmp/workspace_files.txt

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/package.json"
echo "  - /tmp/BUNDLE_ANALYSIS.md"
echo "  - /tmp/workspace_files.txt"