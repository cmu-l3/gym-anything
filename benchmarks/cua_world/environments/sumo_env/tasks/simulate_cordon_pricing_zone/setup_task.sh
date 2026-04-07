#!/bin/bash
echo "=== Setting up simulate_cordon_pricing_zone task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/SUMO_Output
rm -rf /home/ga/SUMO_Output/*
chown -R ga:ga /home/ga/SUMO_Output

# Make sure no SUMO GUI or terminal is left over from previous tasks
kill_sumo
pkill -f "gnome-terminal" || true
sleep 1

# Start a terminal in the scenario directory for the user
echo "Starting terminal for agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"

# Wait for terminal to appear
sleep 3
wait_for_window "Terminal" 10

# Maximize the terminal
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="