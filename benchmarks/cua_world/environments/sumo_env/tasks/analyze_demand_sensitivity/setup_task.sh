#!/bin/bash
echo "=== Setting up analyze_demand_sensitivity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous SUMO processes
kill_sumo

# Ensure output directory is clean
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Open a terminal for the user in the correct directory
# Wait a brief moment for the desktop environment to be ready
sleep 2
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"

# Wait for terminal window to appear
sleep 3
wait_for_window "Terminal" 10

# Maximize the terminal for the agent
focus_and_maximize "Terminal"

# Take initial screenshot of the starting state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="