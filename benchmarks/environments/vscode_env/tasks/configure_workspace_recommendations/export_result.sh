#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Workspace Recommendations Result ==="

WORKSPACE_DIR="/home/ga/workspace/team_project"
VSCODE_DIR="$WORKSPACE_DIR/.vscode"
EXTENSIONS_JSON="$VSCODE_DIR/extensions.json"

# Try to focus VSCode and save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Give time for any file operations to complete
sleep 2

# Check if .vscode directory exists
if [ -d "$VSCODE_DIR" ]; then
    echo "✅ .vscode directory exists"
    ls -la "$VSCODE_DIR" > /tmp/vscode_dir_listing.txt 2>&1
else
    echo "⚠️ .vscode directory not found at $VSCODE_DIR"
    echo "DIRECTORY_NOT_FOUND" > /tmp/vscode_dir_listing.txt
fi

# Check if extensions.json exists and copy to /tmp for verifier
if [ -f "$EXTENSIONS_JSON" ]; then
    echo "✅ extensions.json found"
    cp "$EXTENSIONS_JSON" /tmp/extensions.json 2>&1 || echo "Failed to copy"
    
    # Also output content for debugging
    echo "Content preview:"
    head -20 "$EXTENSIONS_JSON" || echo "Could not read file"
else
    echo "⚠️ extensions.json not found at $EXTENSIONS_JSON"
    echo "{\"error\": \"file_not_found\"}" > /tmp/extensions.json
fi

# Export workspace structure for debugging
find "$WORKSPACE_DIR" -maxdepth 2 -type f > /tmp/workspace_structure.txt 2>&1 || echo "Could not list workspace"

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Target file: $EXTENSIONS_JSON"