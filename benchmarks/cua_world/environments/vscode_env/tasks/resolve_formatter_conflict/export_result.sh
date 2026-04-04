#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Resolve Formatter Conflict Result ==="

WORKSPACE_DIR="/home/ga/workspace/webapp"
EXPORT_DIR="/tmp/formatter_conflict_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Give VSCode time to save files
sleep 2

# Try to focus and save any unsaved files
focus_vscode_window 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+s" 2>/dev/null || true
sleep 1

# Export configuration files for verification
echo "Exporting package.json..."
if [ -f "$WORKSPACE_DIR/package.json" ]; then
    cp "$WORKSPACE_DIR/package.json" "$EXPORT_DIR/" 2>/dev/null || true
    echo "✓ package.json exported"
else
    echo "⚠️ package.json not found"
fi

echo "Exporting .eslintrc.json..."
if [ -f "$WORKSPACE_DIR/.eslintrc.json" ]; then
    cp "$WORKSPACE_DIR/.eslintrc.json" "$EXPORT_DIR/" 2>/dev/null || true
    echo "✓ .eslintrc.json exported"
else
    echo "⚠️ .eslintrc.json not found"
fi

# Also check node_modules for installed package
echo "Checking node_modules..."
if [ -d "$WORKSPACE_DIR/node_modules/eslint-config-prettier" ]; then
    echo "eslint-config-prettier" > "$EXPORT_DIR/installed_packages.txt"
    echo "✓ eslint-config-prettier found in node_modules"
else
    echo "" > "$EXPORT_DIR/installed_packages.txt"
    echo "⚠️ eslint-config-prettier NOT found in node_modules"
fi

# List installed packages for debugging
if [ -f "$WORKSPACE_DIR/package.json" ]; then
    cd "$WORKSPACE_DIR"
    npm list --depth=0 2>/dev/null | grep eslint > "$EXPORT_DIR/npm_list.txt" || echo "" > "$EXPORT_DIR/npm_list.txt"
fi

echo "✅ Export complete"
echo "Exported to: $EXPORT_DIR"
ls -la "$EXPORT_DIR"