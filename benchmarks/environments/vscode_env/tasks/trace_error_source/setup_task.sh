#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Trace Error Source Task ==="

WORKSPACE_DIR="/home/ga/workspace/user_service"
TASK_ASSETS="/workspace/tasks/trace_error_source/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Copy asset files to workspace
echo "Copying source files..."
sudo -u ga cp "$TASK_ASSETS/main.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/data_processor.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/models.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/utils.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/error_output.txt" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/sample_data.json" "$WORKSPACE_DIR/"

# Ensure proper ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace and error file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/error_output.txt'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Trace Error Source Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read error_output.txt to analyze the stack trace"
echo "  2. Identify the failing line (line 67 in data_processor.py)"
echo "  3. Create investigation_notes.md with root cause analysis"
echo "  4. Add comments to data_processor.py explaining the bug"
echo "  5. Fix the bug by adding None check before .get() call"
echo "  6. Save all files (Ctrl+S)"