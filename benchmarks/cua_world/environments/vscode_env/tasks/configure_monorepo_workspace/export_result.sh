#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Monorepo Workspace Result ==="

WORKSPACE_DIR="/home/ga/workspace/monorepo-project"

# Ensure VSCode has saved any open files
focus_vscode_window
sleep 1
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save all; continuing"
}

# Wait a moment for files to be written
sleep 2

# Export workspace settings if it exists
SETTINGS_FILE="$WORKSPACE_DIR/.vscode/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    echo "Copying workspace settings..."
    cp "$SETTINGS_FILE" /tmp/workspace_settings.json 2>&1 || echo "{}" > /tmp/workspace_settings.json
    echo "✅ Settings exported"
else
    echo "⚠️ No workspace settings found"
    echo "{}" > /tmp/workspace_settings.json
fi

# Export root tsconfig.json
ROOT_TSCONFIG="$WORKSPACE_DIR/tsconfig.json"
if [ -f "$ROOT_TSCONFIG" ]; then
    echo "Copying root tsconfig..."
    cp "$ROOT_TSCONFIG" /tmp/root_tsconfig.json 2>&1 || echo "{}" > /tmp/root_tsconfig.json
    echo "✅ Root tsconfig exported"
else
    echo "⚠️ No root tsconfig found"
    echo "{}" > /tmp/root_tsconfig.json
fi

# Export package tsconfig files
echo "Copying package tsconfig files..."
mkdir -p /tmp/package_tsconfigs

for pkg in shared-utils ui-components api-client backend; do
    PKG_TSCONFIG="$WORKSPACE_DIR/packages/$pkg/tsconfig.json"
    if [ -f "$PKG_TSCONFIG" ]; then
        cp "$PKG_TSCONFIG" "/tmp/package_tsconfigs/${pkg}_tsconfig.json" 2>&1 || echo "{}" > "/tmp/package_tsconfigs/${pkg}_tsconfig.json"
        echo "  ✅ $pkg tsconfig exported"
    else
        echo "  ⚠️ $pkg tsconfig not found"
        echo "{}" > "/tmp/package_tsconfigs/${pkg}_tsconfig.json"
    fi
done

# Export directory structure for debugging
echo "Exporting directory structure..."
ls -laR "$WORKSPACE_DIR/.vscode/" > /tmp/vscode_dir_structure.txt 2>&1 || echo "No .vscode directory" > /tmp/vscode_dir_structure.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Exported files to /tmp for verification"