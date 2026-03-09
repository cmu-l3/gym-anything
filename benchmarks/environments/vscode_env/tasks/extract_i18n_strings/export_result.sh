#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract i18n Strings Result ==="

WORKSPACE_DIR="/home/ga/workspace/dashboard-app"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

echo "Saving all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for key files to be written
wait_for_file "$WORKSPACE_DIR/src/components/Header.jsx" 3
wait_for_file "$WORKSPACE_DIR/src/components/LoginForm.jsx" 3
wait_for_file "$WORKSPACE_DIR/src/components/Dashboard.jsx" 3

# Check if translation file was created
if [ -f "$WORKSPACE_DIR/src/locales/en.json" ]; then
    echo "✅ Translation file created: src/locales/en.json"
else
    echo "⚠️ Translation file not found: src/locales/en.json"
fi

# Check if config file was created
if [ -f "$WORKSPACE_DIR/src/i18nConfig.js" ]; then
    echo "✅ Config file created: src/i18nConfig.js"
else
    echo "⚠️ Config file not found: src/i18nConfig.js"
fi

echo "✅ Export complete"
echo "Files location: $WORKSPACE_DIR"