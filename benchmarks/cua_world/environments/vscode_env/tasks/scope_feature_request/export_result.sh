#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Scope Feature Request Result ==="

WORKSPACE_DIR="/home/ga/workspace/analytics_platform"
SCOPE_DOC="$WORKSPACE_DIR/SCOPE_CSV_VALIDATION.md"

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait a moment for file to be written
sleep 2

# Export the scope document if it exists
if [ -f "$SCOPE_DOC" ]; then
    echo "Copying scope document to /tmp..."
    sudo -u ga cp "$SCOPE_DOC" /tmp/SCOPE_CSV_VALIDATION.md
    echo "✅ Scope document exported"
    echo "Document size: $(wc -c < /tmp/SCOPE_CSV_VALIDATION.md) bytes"
else
    echo "⚠️ Scope document not found at $SCOPE_DOC"
    echo "" > /tmp/SCOPE_CSV_VALIDATION.md
fi

# Check git status to verify no code changes
cd "$WORKSPACE_DIR"
sudo -u ga git status --porcelain > /tmp/git_status_scope.txt 2>&1 || echo "" > /tmp/git_status_scope.txt

# List files in workspace for verification
ls -la "$WORKSPACE_DIR" > /tmp/workspace_files.txt 2>&1 || echo "" > /tmp/workspace_files.txt

echo "✅ Export complete"
echo "Scope document: $SCOPE_DOC"