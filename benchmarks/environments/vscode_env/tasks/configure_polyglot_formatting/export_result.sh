#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Formatter Configuration Result ==="

# Give VSCode time to save settings
sleep 2

# Export workspace settings if it exists
WORKSPACE_SETTINGS="/home/ga/workspace/polyglot_project/.vscode/settings.json"
if [ -f "$WORKSPACE_SETTINGS" ]; then
    echo "Exporting workspace settings..."
    cp "$WORKSPACE_SETTINGS" /tmp/workspace_settings.json 2>&1 || echo "{}" > /tmp/workspace_settings.json
    echo "✅ Workspace settings exported"
else
    echo "⚠️ Workspace settings not found, creating empty file"
    echo "{}" > /tmp/workspace_settings.json
fi

# Export user settings if it exists
USER_SETTINGS="/home/ga/.config/Code/User/settings.json"
if [ -f "$USER_SETTINGS" ]; then
    echo "Exporting user settings..."
    cp "$USER_SETTINGS" /tmp/user_settings.json 2>&1 || echo "{}" > /tmp/user_settings.json
    echo "✅ User settings exported"
else
    echo "⚠️ User settings not found, creating empty file"
    echo "{}" > /tmp/user_settings.json
fi

# List settings files for debugging
echo ""
echo "Settings files status:"
echo "Workspace settings: $([ -f "$WORKSPACE_SETTINGS" ] && echo 'EXISTS' || echo 'NOT FOUND')"
echo "User settings: $([ -f "$USER_SETTINGS" ] && echo 'EXISTS' || echo 'NOT FOUND')"

if [ -f "$WORKSPACE_SETTINGS" ]; then
    echo ""
    echo "Workspace settings preview:"
    head -20 "$WORKSPACE_SETTINGS" || true
fi

echo ""
echo "✅ Export complete"
echo "Exported to: /tmp/workspace_settings.json, /tmp/user_settings.json"