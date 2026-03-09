#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Custom File Viewer Result ==="

WORKSPACE="/home/ga/workspace/db_debug"

# Try to save any open files
echo "Attempting to save open files..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save via keyboard shortcut; continuing"
}

# Wait for files to be written
sleep 2

# Export workspace settings if they exist
mkdir -p /tmp/vscode_export
if [ -f "$WORKSPACE/.vscode/settings.json" ]; then
    echo "Exporting workspace settings..."
    cp "$WORKSPACE/.vscode/settings.json" /tmp/vscode_export/workspace_settings.json 2>/dev/null || true
fi

# Export user settings
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    echo "Exporting user settings..."
    cp "/home/ga/.config/Code/User/settings.json" /tmp/vscode_export/user_settings.json 2>/dev/null || true
fi

# Export investigation notes
if [ -f "$WORKSPACE/investigation_notes.txt" ]; then
    echo "Exporting investigation notes..."
    cp "$WORKSPACE/investigation_notes.txt" /tmp/vscode_export/investigation_notes.txt 2>/dev/null || true
else
    echo "⚠️ Investigation notes file not found"
    echo "File not found" > /tmp/vscode_export/investigation_notes.txt
fi

# List installed extensions
echo "Exporting installed extensions..."
su - ga -c "DISPLAY=:1 code --list-extensions > /tmp/vscode_export/installed_extensions.txt 2>&1" || echo "" > /tmp/vscode_export/installed_extensions.txt

# List extensions directory
ls -la /home/ga/.vscode/extensions/ > /tmp/vscode_export/extensions_dir_list.txt 2>&1 || echo "No extensions directory" > /tmp/vscode_export/extensions_dir_list.txt

echo "✅ Export complete"
echo "Exported to: /tmp/vscode_export/"
echo ""
echo "Checking investigation notes content:"
cat /tmp/vscode_export/investigation_notes.txt 2>/dev/null || echo "Notes file not accessible"