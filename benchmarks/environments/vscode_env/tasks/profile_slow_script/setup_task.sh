#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Profile Slow Script Task ==="

WORKSPACE_DIR="/home/ga/workspace/profile_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Copy assets
ASSETS_DIR="/workspace/tasks/profile_slow_script/assets"
sudo -u ga cp "$ASSETS_DIR/data_processor.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/input_data.csv" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/README.txt" "$WORKSPACE_DIR/"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2

# Open the main script and README
su - ga -c "DISPLAY=:1 code -r '$WORKSPACE_DIR/data_processor.py'" &
sleep 1
su - ga -c "DISPLAY=:1 code -r '$WORKSPACE_DIR/README.txt'" &
sleep 1

focus_vscode_window

echo "=== Profile Slow Script Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open data_processor.py and read the script structure"
echo "  2. Add timing instrumentation (import time, time.perf_counter())"
echo "  3. Measure each stage: read, validate, transform, write"
echo "  4. Run script: python data_processor.py"
echo "  5. Identify bottleneck from timing output"
echo "  6. Document findings in performance_analysis.md"