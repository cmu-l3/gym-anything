#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting VSCode Recovery Result ==="

WORKSPACE="/home/ga/workspace/bugfix-project"

# Ensure any open files are saved
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s  # Save all
} || {
    echo "⚠️ Failed to save files; continuing"
}

sleep 2

# List recovered files for debugging
echo "Checking recovered files..."
ls -la "$WORKSPACE/src/" 2>/dev/null || echo "src/ directory empty or not found"
ls -la "$WORKSPACE/config/" 2>/dev/null || echo "config/ directory empty or not found"
ls -la "$WORKSPACE/docs/" 2>/dev/null || echo "docs/ directory empty or not found"

# Copy files to /tmp for easier verification (optional, verifier will copy directly)
echo "Exporting file status..."
if [ -f "$WORKSPACE/src/authentication.py" ]; then
    echo "✅ authentication.py found"
else
    echo "❌ authentication.py missing"
fi

if [ -f "$WORKSPACE/config/user_settings.json" ]; then
    echo "✅ user_settings.json found"
else
    echo "❌ user_settings.json missing"
fi

if [ -f "$WORKSPACE/docs/URGENT_NOTES.md" ]; then
    echo "✅ URGENT_NOTES.md found"
else
    echo "❌ URGENT_NOTES.md missing"
fi

echo "=== Export complete ==="