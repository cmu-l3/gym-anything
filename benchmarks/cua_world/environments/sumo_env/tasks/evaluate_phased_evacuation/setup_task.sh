#!/bin/bash
echo "=== Setting up evaluate_phased_evacuation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Clean previous task state if any
rm -rf /home/ga/SUMO_Scenarios/evacuation 2>/dev/null
rm -f /tmp/evac_*.xml /tmp/task_result.json /tmp/metrics.json 2>/dev/null

# Open a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios &"
    sleep 3
fi

# Focus terminal
focus_and_maximize "Terminal"

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="