#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Internationalize Strings Result ==="

WORKSPACE_DIR="/home/ga/workspace/i18n_task"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s  # Save All
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s  # Additional save
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

sleep 2

# Wait for files to be written
wait_for_file "$WORKSPACE_DIR/app.js" 5

# Export directory listing for verification
ls -laR "$WORKSPACE_DIR" > /tmp/i18n_workspace_listing.txt 2>&1 || echo "Failed to list workspace" > /tmp/i18n_workspace_listing.txt

# Check if translation file exists and export its location info
if [ -f "$WORKSPACE_DIR/i18n/en.json" ]; then
    echo "TRANSLATION_FILE_FOUND: i18n/en.json" > /tmp/i18n_translation_found.txt
elif [ -f "$WORKSPACE_DIR/locales/en.json" ]; then
    echo "TRANSLATION_FILE_FOUND: locales/en.json" > /tmp/i18n_translation_found.txt
elif [ -f "$WORKSPACE_DIR/translations.json" ]; then
    echo "TRANSLATION_FILE_FOUND: translations.json" > /tmp/i18n_translation_found.txt
else
    echo "TRANSLATION_FILE_NOT_FOUND" > /tmp/i18n_translation_found.txt
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Check for: i18n/en.json and modified app.js"