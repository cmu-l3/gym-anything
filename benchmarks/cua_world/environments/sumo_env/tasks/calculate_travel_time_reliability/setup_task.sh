#!/bin/bash
echo "=== Setting up calculate_travel_time_reliability task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure SUMO output directory exists and is clean
OUTPUT_DIR="/home/ga/SUMO_Output"
rm -rf "$OUTPUT_DIR" 2>/dev/null || true
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Launch terminal for the agent in the working directory
echo "Starting terminal for the agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"

# Wait for terminal window to appear
sleep 3
wait_for_window "Terminal" 10

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="