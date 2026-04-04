#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Custom File Associations Result ==="

# Focus VSCode and save to ensure settings are persisted
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; settings may already be saved"
}

sleep 2

# Settings are automatically saved to disk by VSCode
# We just need to ensure any open settings editor is saved

echo "✅ Export complete"
echo "Settings file: /home/ga/.config/Code/User/settings.json"

# Verify settings file exists
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    echo "✓ Settings file found"
    # Show file associations if they exist
    if command -v jq &> /dev/null; then
        echo "Current file associations:"
        sudo -u ga jq '.["files.associations"]' /home/ga/.config/Code/User/settings.json 2>/dev/null || echo "  (none or error reading)"
    fi
else
    echo "⚠️ Settings file not found"
fi