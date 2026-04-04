#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Resolve Circular Imports Result ==="

WORKSPACE_DIR="/home/ga/workspace/api-project"
SRC_DIR="$WORKSPACE_DIR/src"

# Save all open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 100 ctrl+s
} || {
    echo "⚠️ Failed to save files; continuing"
}

sleep 2

# Export source files to /tmp for verification
echo "Exporting source files..."
mkdir -p /tmp/circular_imports_export
cp -f "$SRC_DIR/validation.js" /tmp/circular_imports_export/validation.js 2>/dev/null || echo "" > /tmp/circular_imports_export/validation.js
cp -f "$SRC_DIR/formatting.js" /tmp/circular_imports_export/formatting.js 2>/dev/null || echo "" > /tmp/circular_imports_export/formatting.js
cp -f "$SRC_DIR/database.js" /tmp/circular_imports_export/database.js 2>/dev/null || echo "" > /tmp/circular_imports_export/database.js
cp -f "$SRC_DIR/constants.js" /tmp/circular_imports_export/constants.js 2>/dev/null || echo "" > /tmp/circular_imports_export/constants.js

# Test if application can load
echo "Testing application load..."
cd "$WORKSPACE_DIR"
timeout 5 sudo -u ga node index.js > /tmp/circular_imports_app_output.txt 2>&1
APP_EXIT_CODE=$?
echo $APP_EXIT_CODE > /tmp/circular_imports_exit_code.txt

# Run madge to check for circular dependencies
echo "Running circular dependency check..."
cd "$WORKSPACE_DIR"
sudo -u ga npx madge --circular src/ --json > /tmp/circular_imports_madge.json 2>&1 || echo "[]" > /tmp/circular_imports_madge.json

echo "✅ Export complete"
echo "Files exported to: /tmp/circular_imports_export/"
echo "Application exit code: $APP_EXIT_CODE"