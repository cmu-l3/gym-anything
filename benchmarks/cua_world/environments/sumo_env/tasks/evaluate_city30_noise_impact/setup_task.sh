#!/bin/bash
echo "=== Setting up City 30 Noise Impact task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/SUMO_Output
rm -rf /home/ga/SUMO_Output/*
chown -R ga:ga /home/ga/SUMO_Output

# Make sure base scenario is intact
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/

# Open a terminal for the user since this is a heavy CLI/scripting task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio/ &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Clear screen
DISPLAY=:1 xdotool type "clear"
DISPLAY=:1 xdotool key Return

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="