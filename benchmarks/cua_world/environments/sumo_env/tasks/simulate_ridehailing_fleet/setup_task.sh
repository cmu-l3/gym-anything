#!/bin/bash
echo "=== Setting up simulate_ridehailing_fleet task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure clean slate for the task
rm -rf /home/ga/SUMO_Scenarios/ridehailing 2>/dev/null || true

# Launch terminal for the agent to use
echo "Launching terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga >/tmp/terminal.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 x-terminal-emulator >/tmp/terminal.log 2>&1 &"

# Wait for terminal window to appear
sleep 3
wait_for_window "Terminal\|x-terminal-emulator" 30

# Focus and maximize the terminal
focus_and_maximize "Terminal\|x-terminal-emulator"
sleep 1

# Take initial screenshot showing clean terminal
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="