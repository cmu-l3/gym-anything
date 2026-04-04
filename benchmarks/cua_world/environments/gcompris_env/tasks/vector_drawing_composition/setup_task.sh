#!/bin/bash
echo "=== Setting up vector_drawing_composition task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/drawing_composition.png
rm -f /tmp/task_result.json

# 3. Kill any existing GCompris instances
kill_gcompris

# 4. Launch GCompris at the main menu
# The agent must navigate to the specific activity themselves
echo "Launching GCompris..."
launch_gcompris
sleep 5

# 5. Maximize window for best visibility
maximize_gcompris

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCompris is running."
echo "Agent goal: Open Vector Drawing -> Draw House + Sun -> Screenshot to ~/Documents/drawing_composition.png"