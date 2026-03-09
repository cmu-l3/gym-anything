#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Broken IntelliSense Result ==="

WORKSPACE_DIR="/home/ga/workspace/ml_project"

# Give time for any pending settings saves
sleep 2

# Focus VSCode and save any unsaved settings
focus_vscode_window || true
sleep 1

# Export workspace settings
if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    echo "Exporting workspace settings..."
    cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/workspace_settings.json 2>&1 || echo "{}" > /tmp/workspace_settings.json
else
    echo "No workspace settings found"
    echo "{}" > /tmp/workspace_settings.json
fi

# Export user settings
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    echo "Exporting user settings..."
    cp "/home/ga/.config/Code/User/settings.json" /tmp/user_settings.json 2>&1 || echo "{}" > /tmp/user_settings.json
else
    echo "No user settings found"
    echo "{}" > /tmp/user_settings.json
fi

# Export installed extensions list
echo "Exporting extensions list..."
sudo -u ga bash -c "DISPLAY=:1 code --list-extensions" > /tmp/extensions_list.txt 2>&1 || echo "Could not list extensions" > /tmp/extensions_list.txt

# Export extensions directory structure (to verify Pylance is present)
if [ -d "/home/ga/.vscode/extensions" ]; then
    ls -la /home/ga/.vscode/extensions/ | grep -iE "(python|pylance)" > /tmp/extensions_dir.txt 2>&1 || echo "No Python extensions found" > /tmp/extensions_dir.txt
else
    echo "Extensions directory not found" > /tmp/extensions_dir.txt
fi

# Check if venv interpreter exists (for verification reference)
if [ -f "$WORKSPACE_DIR/venv/bin/python" ]; then
    echo "$WORKSPACE_DIR/venv/bin/python" > /tmp/venv_interpreter_path.txt
    # Also get absolute path
    readlink -f "$WORKSPACE_DIR/venv/bin/python" >> /tmp/venv_interpreter_path.txt 2>&1 || true
else
    echo "venv interpreter not found" > /tmp/venv_interpreter_path.txt
fi

# Export Python files (to verify they still exist)
if [ -f "$WORKSPACE_DIR/data_analysis.py" ]; then
    cp "$WORKSPACE_DIR/data_analysis.py" /tmp/data_analysis.py 2>&1 || true
fi

# Take screenshot of final state
echo "Taking screenshot..."
su - ga -c "DISPLAY=:1 import -window root /tmp/vscode_final_screenshot.png" 2>&1 || echo "Screenshot failed"

echo "✅ Export complete"
echo "Exported files:"
echo "  - /tmp/workspace_settings.json"
echo "  - /tmp/user_settings.json"
echo "  - /tmp/extensions_list.txt"
echo "  - /tmp/extensions_dir.txt"
echo "  - /tmp/venv_interpreter_path.txt"
echo "  - /tmp/vscode_final_screenshot.png"