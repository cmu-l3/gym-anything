#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Team Devcontainer Configuration Result ==="

WORKSPACE_DIR="/home/ga/workspace/team-project"
DEVCONTAINER_DIR="$WORKSPACE_DIR/.devcontainer"
DEVCONTAINER_FILE="$DEVCONTAINER_DIR/devcontainer.json"
README_FILE="$WORKSPACE_DIR/README_DEVCONTAINER.md"

# Save file to VSCode if currently editing
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save file; continuing"
}

# Export devcontainer.json to /tmp for verification
if [ -f "$DEVCONTAINER_FILE" ]; then
    echo "Exporting devcontainer.json..."
    cp "$DEVCONTAINER_FILE" /tmp/devcontainer.json 2>&1 || echo "{}" > /tmp/devcontainer.json
    echo "✅ Devcontainer file exported"
else
    echo "⚠️ Devcontainer file not found at $DEVCONTAINER_FILE"
    echo "{}" > /tmp/devcontainer.json
fi

# Export README_DEVCONTAINER.md to /tmp
if [ -f "$README_FILE" ]; then
    echo "Exporting README_DEVCONTAINER.md..."
    cp "$README_FILE" /tmp/README_DEVCONTAINER.md 2>&1 || echo "" > /tmp/README_DEVCONTAINER.md
    echo "✅ README file exported"
else
    echo "⚠️ README_DEVCONTAINER.md not found"
    echo "" > /tmp/README_DEVCONTAINER.md
fi

# Export directory structure for verification
ls -la "$WORKSPACE_DIR/" > /tmp/workspace_structure.txt 2>&1 || echo "No workspace" > /tmp/workspace_structure.txt
if [ -d "$DEVCONTAINER_DIR" ]; then
    ls -la "$DEVCONTAINER_DIR/" > /tmp/devcontainer_structure.txt 2>&1
else
    echo "No .devcontainer directory" > /tmp/devcontainer_structure.txt
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Devcontainer config: $DEVCONTAINER_FILE"