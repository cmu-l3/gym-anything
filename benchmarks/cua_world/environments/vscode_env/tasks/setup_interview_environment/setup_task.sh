#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Interview Environment Task ==="

# Remove any existing interview workspace to start fresh
if [ -d "/home/ga/interview_workspace" ]; then
    echo "Removing existing interview workspace..."
    rm -rf /home/ga/interview_workspace
fi

# Ensure VSCode user directory exists
sudo -u ga mkdir -p /home/ga/.config/Code/User

# Close any open VSCode instances to start fresh
echo "Closing any existing VSCode instances..."
pkill -f "code" || true
sleep 2

# Start VSCode with a blank workspace
echo "Starting VSCode..."
su - ga -c "DISPLAY=:1 code --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Interview Environment Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create workspace directory: /home/ga/interview_workspace/"
echo "  2. Create .vscode/ subdirectory inside workspace"
echo "  3. Create .vscode/settings.json with professional settings:"
echo "     - workbench.colorTheme: 'Default Light+'"
echo "     - editor.fontSize: 14"
echo "     - files.autoSave: 'afterDelay'"
echo "     - editor.minimap.enabled: false"
echo "     - workbench.activityBar.visible: false"
echo "  4. Create .vscode/tasks.json with three language runners:"
echo "     - Python: python3 \${file}"
echo "     - JavaScript: node \${file}"
echo "     - Java: javac + java execution"
echo "  5. Create three starter files:"
echo "     - starter.py (with function template)"
echo "     - starter.js (with function template)"
echo "     - Starter.java (with class template)"
echo "  6. Open VSCode with the interview_workspace directory"