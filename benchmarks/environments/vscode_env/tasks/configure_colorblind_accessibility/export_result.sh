#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Colorblind Accessibility Configuration Result ==="

# Focus VSCode and save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

# Give VSCode time to write settings
sleep 2

# Export settings.json to /tmp for verifier
SETTINGS_PATH="/home/ga/.config/Code/User/settings.json"
if [ -f "$SETTINGS_PATH" ]; then
    echo "Exporting settings.json..."
    cp "$SETTINGS_PATH" /tmp/vscode_settings.json 2>&1 || echo "{}" > /tmp/vscode_settings.json
    echo "✅ Settings exported to /tmp/vscode_settings.json"
else
    echo "⚠️ Settings file not found at $SETTINGS_PATH"
    echo "{}" > /tmp/vscode_settings.json
fi

# Export installed extensions list
echo "Exporting extensions list..."
ls -1 /home/ga/.vscode/extensions/ > /tmp/vscode_extensions_dirs.txt 2>&1 || echo "" > /tmp/vscode_extensions_dirs.txt

# Also get code --list-extensions output
su - ga -c "DISPLAY=:1 code --list-extensions > /tmp/vscode_extensions_ids.txt 2>&1" || echo "" > /tmp/vscode_extensions_ids.txt

# Take a screenshot for manual verification (optional)
su - ga -c "DISPLAY=:1 import -window root /tmp/vscode_screenshot.png" 2>/dev/null || true

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/vscode_settings.json"
echo "  - /tmp/vscode_extensions_dirs.txt"
echo "  - /tmp/vscode_extensions_ids.txt"
echo "  - /tmp/vscode_screenshot.png (if available)"

# Display settings for debugging
if [ -f /tmp/vscode_settings.json ]; then
    echo ""
    echo "Current settings.json content:"
    cat /tmp/vscode_settings.json | head -50
fi