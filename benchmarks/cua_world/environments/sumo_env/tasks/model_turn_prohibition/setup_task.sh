#!/bin/bash
echo "=== Setting up model_turn_prohibition task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure SUMO Output directory is clean and ready
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/*
chown -R ga:ga /home/ga/SUMO_Output

# Make sure scenarios are owned by ga user to prevent permission errors
chown -R ga:ga /home/ga/SUMO_Scenarios

# Ensure no SUMO instances are running from previous tasks
kill_sumo

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Wait for terminal to appear and maximize it
wait_for_window "Terminal" 10
focus_and_maximize "Terminal"

# Take initial screenshot showing clean state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="