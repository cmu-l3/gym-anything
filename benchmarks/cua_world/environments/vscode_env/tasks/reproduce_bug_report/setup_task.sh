#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bug Reproduction Task ==="

WORKSPACE_DIR="/home/ga/workspace/bug_repro"
ASSETS_DIR="/workspace/tasks/reproduce_bug_report/assets"

# Create clean workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Copy buggy script and bug report
if [ -f "$ASSETS_DIR/data_processor.py" ]; then
    sudo -u ga cp "$ASSETS_DIR/data_processor.py" "$WORKSPACE_DIR/"
    echo "✓ Copied data_processor.py"
else
    echo "⚠️ Warning: data_processor.py not found in assets"
fi

if [ -f "$ASSETS_DIR/BUG_REPORT.txt" ]; then
    sudo -u ga cp "$ASSETS_DIR/BUG_REPORT.txt" "$WORKSPACE_DIR/"
    echo "✓ Copied BUG_REPORT.txt"
else
    echo "⚠️ Warning: BUG_REPORT.txt not found in assets"
fi

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace and bug report visible
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/BUG_REPORT.txt'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Bug Reproduction Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read BUG_REPORT.txt to understand the issue"
echo "  2. Create test_bug_input.csv with empty numeric fields"
echo "  3. Open terminal (Ctrl+\`) and run: python data_processor.py test_bug_input.csv"
echo "  4. Create REPRODUCTION.md with steps, error message, and behavior description"