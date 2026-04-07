#!/bin/bash
echo "=== Setting up evaluate_hov_lane_policy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean output directory to ensure a fresh state
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/* 2>/dev/null || true
chown -R ga:ga /home/ga/SUMO_Output

# Make sure we're not running any previous SUMO processes
kill_sumo
sleep 1

# Open a terminal in the target directory for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Output > /dev/null 2>&1 &"
sleep 2

# Focus and maximize terminal
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="