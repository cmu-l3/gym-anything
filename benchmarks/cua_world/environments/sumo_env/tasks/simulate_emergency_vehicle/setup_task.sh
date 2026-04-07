#!/bin/bash
echo "=== Setting up simulate_emergency_vehicle task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any potential leftover files from previous runs
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/ambulance.rou.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_emergency.sumocfg 2>/dev/null || true
rm -f /home/ga/SUMO_Output/tripinfos.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Output/ambulance_report.json 2>/dev/null || true

# Open a terminal for the agent if one isn't open
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 2
fi

# Maximize terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="