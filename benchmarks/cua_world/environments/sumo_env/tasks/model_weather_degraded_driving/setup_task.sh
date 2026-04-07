#!/bin/bash
echo "=== Setting up Weather Degraded Driving Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SUMO processes are killed
kill_sumo
sleep 1

# Reset and clean the workspace
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Make sure baseline run_rain configs from previous failed attempts are deleted
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_rain.sumocfg 2>/dev/null || true

# Launch a terminal for the user (since it's a CLI/XML editing task)
if ! pgrep -f gnome-terminal > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio/ &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="