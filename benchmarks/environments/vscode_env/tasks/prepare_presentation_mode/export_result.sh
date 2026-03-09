#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Presentation Mode Result ==="

# Give VSCode time to save settings if recently modified
sleep 2

# Try to save any open files (in case settings were edited directly)
focus_vscode_window
{
  su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+s" || true
  sleep 1
} 2>/dev/null

# Export settings files to /tmp for verifier
echo "Exporting VSCode settings..."

# User settings (most likely location for changes)
if [ -f /home/ga/.config/Code/User/settings.json ]; then
    cp /home/ga/.config/Code/User/settings.json /tmp/user_settings.json
    echo "✅ User settings copied"
    cat /tmp/user_settings.json
else
    echo "{}" > /tmp/user_settings.json
    echo "⚠️ User settings not found"
fi

# Workspace settings (might be used instead)
if [ -f /home/ga/workspace/demo_project/.vscode/settings.json ]; then
    cp /home/ga/workspace/demo_project/.vscode/settings.json /tmp/workspace_settings.json
    echo "✅ Workspace settings copied"
else
    echo "{}" > /tmp/workspace_settings.json
    echo "⚠️ Workspace settings not found (this is OK)"
fi

# Optional: Take screenshot for visual verification fallback
{
  su - ga -c "DISPLAY=:1 import -window root /tmp/vscode_presentation_screenshot.png" 2>/dev/null || \
  su - ga -c "DISPLAY=:1 scrot /tmp/vscode_presentation_screenshot.png" 2>/dev/null || \
  echo "Screenshot capture skipped"
} || true

echo ""
echo "✅ Export complete"
echo "Files exported to /tmp:"
echo "  - user_settings.json"
echo "  - workspace_settings.json"
echo "  - vscode_presentation_screenshot.png (optional)"