#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Migrate IntelliJ Keymap Result ==="

KEYBINDINGS_FILE="/home/ga/.config/Code/User/keybindings.json"

# Give VSCode time to save settings
sleep 2

# Ensure file is saved (try to focus VSCode and save)
{
    focus_vscode_window
    safe_xdotool ga :1 key --delay 100 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not focus VSCode for save; continuing"
}

# Copy keybindings to /tmp for easier verification access
if [ -f "$KEYBINDINGS_FILE" ]; then
    echo "Copying keybindings to /tmp..."
    cp "$KEYBINDINGS_FILE" /tmp/keybindings.json
    
    echo "Keybindings file content:"
    cat "$KEYBINDINGS_FILE"
    
    echo "✅ Keybindings exported to /tmp/keybindings.json"
else
    echo "⚠️ Keybindings file not found at $KEYBINDINGS_FILE"
    echo "[]" > /tmp/keybindings.json
fi

# Also list all settings files for debugging
echo ""
echo "VSCode User directory contents:"
ls -la /home/ga/.config/Code/User/ || echo "User directory not found"

echo "✅ Export complete"