#!/bin/bash
echo "=== Setting up analyze_intersection_queues task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure a fresh environment by restoring the pristine scenario
rm -rf /home/ga/SUMO_Scenarios/bologna_pasubio
mkdir -p /home/ga/SUMO_Scenarios/bologna_pasubio
cp -r /workspace/data/bologna_pasubio/* /home/ga/SUMO_Scenarios/bologna_pasubio/
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio

# Clear output directory to remove stale results
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

# Start a terminal window for the agent
if ! pgrep -f "gnome-terminal\|x-terminal-emulator" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 x-terminal-emulator &"
    sleep 3
fi

# Focus and maximize the terminal
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="