#!/bin/bash
echo "=== Setting up simulate_signal_power_outage task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create and clean the output directory
mkdir -p /home/ga/SUMO_Output
rm -rf /home/ga/SUMO_Output/*
chown -R ga:ga /home/ga/SUMO_Output

# Make sure SUMO environment variables are set globally
export SUMO_HOME="/usr/share/sumo"

# Kill any existing SUMO or terminal processes
pkill -f "sumo" 2>/dev/null || true
pkill -f "gnome-terminal" 2>/dev/null || true
sleep 1

# Open a terminal in the scenario directory for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"

# Wait for terminal window to appear
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Terminal"; then
        echo "Terminal window detected"
        break
    fi
    sleep 1
done

# Focus and maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Give the UI a moment to settle
sleep 2

# Take initial screenshot as proof of clean state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="