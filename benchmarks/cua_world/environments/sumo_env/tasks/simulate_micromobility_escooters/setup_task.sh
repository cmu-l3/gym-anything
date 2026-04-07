#!/bin/bash
echo "=== Setting up simulate_micromobility_escooters task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any lingering SUMO processes
kill_sumo
sleep 1

# Ensure the output directory is clean and owned by the agent
echo "Preparing workspace..."
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Ensure the baseline directory is pristine
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio

# Open a terminal for the user to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Output &"
    sleep 3
fi

# Maximize the terminal for visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take an initial screenshot to prove a clean starting state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="