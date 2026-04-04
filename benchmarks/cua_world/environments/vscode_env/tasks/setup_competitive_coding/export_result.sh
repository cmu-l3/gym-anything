#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Competitive Coding Setup Result ==="

WORKSPACE_DIR="/home/ga/workspace/cp_contest"

# Ensure all files are saved
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Wait for files to be written
sleep 2

# Verify key files exist
if [ -f "$WORKSPACE_DIR/.vscode/tasks.json" ]; then
    echo "✅ tasks.json exists"
else
    echo "⚠️ tasks.json not found"
fi

if [ -f "$WORKSPACE_DIR/.vscode/keybindings.json" ]; then
    echo "✅ keybindings.json exists"
else
    echo "⚠️ keybindings.json not found"
fi

if [ -f "$WORKSPACE_DIR/.vscode/cp_template.code-snippets" ]; then
    echo "✅ cp_template.code-snippets exists"
else
    echo "⚠️ cp_template.code-snippets not found"
fi

if [ -f "$WORKSPACE_DIR/problem_A.py" ]; then
    echo "✅ problem_A.py exists"
    echo "Solution preview:"
    head -n 10 "$WORKSPACE_DIR/problem_A.py"
else
    echo "⚠️ problem_A.py not found"
fi

echo "✅ Export complete"