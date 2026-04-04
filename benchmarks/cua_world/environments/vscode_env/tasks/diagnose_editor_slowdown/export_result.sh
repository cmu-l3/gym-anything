#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Editor Slowdown Results ==="

WORKSPACE_DIR="/home/ga/workspace/perf_project"
VSCODE_USER_DIR="/home/ga/.config/Code/User"
WORKSPACE_VSCODE="$WORKSPACE_DIR/.vscode"
EXTENSIONS_DIR="/home/ga/.vscode/extensions"

# Try to save any open files
focus_vscode_window || true
{
  safe_xdotool ga :1 key --delay 150 ctrl+shift+s
  sleep 1
} || {
  echo "⚠️ Could not trigger save all; continuing"
}

sleep 2

echo "Exporting workspace settings..."
if [ -f "$WORKSPACE_VSCODE/settings.json" ]; then
  cp "$WORKSPACE_VSCODE/settings.json" /tmp/workspace_settings.json
  echo "✅ Workspace settings exported"
else
  echo "{}" > /tmp/workspace_settings.json
  echo "⚠️ No workspace settings found"
fi

echo "Exporting user settings..."
if [ -f "$VSCODE_USER_DIR/settings.json" ]; then
  cp "$VSCODE_USER_DIR/settings.json" /tmp/user_settings.json
  echo "✅ User settings exported"
else
  echo "{}" > /tmp/user_settings.json
  echo "⚠️ No user settings found"
fi

echo "Exporting performance notes..."
if [ -f "$WORKSPACE_DIR/PERFORMANCE_NOTES.md" ]; then
  cp "$WORKSPACE_DIR/PERFORMANCE_NOTES.md" /tmp/PERFORMANCE_NOTES.md
  echo "✅ Performance notes exported"
else
  echo "" > /tmp/PERFORMANCE_NOTES.md
  echo "⚠️ No PERFORMANCE_NOTES.md found"
fi

echo "Exporting extension list..."
if [ -d "$EXTENSIONS_DIR" ]; then
  ls -1 "$EXTENSIONS_DIR" > /tmp/extension_folders.txt 2>&1
  echo "✅ Extension list exported"
else
  echo "" > /tmp/extension_folders.txt
  echo "⚠️ Extensions directory not found"
fi

echo "Exporting installed extensions via code CLI..."
su - ga -c "DISPLAY=:1 code --list-extensions > /tmp/installed_extensions.txt 2>&1" || echo "" > /tmp/installed_extensions.txt

echo ""
echo "✅ Export complete"
echo "Exported files:"
echo "  - /tmp/workspace_settings.json"
echo "  - /tmp/user_settings.json"
echo "  - /tmp/PERFORMANCE_NOTES.md"
echo "  - /tmp/extension_folders.txt"
echo "  - /tmp/installed_extensions.txt"