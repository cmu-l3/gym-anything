#!/bin/bash
echo "=== Setting up aggregate_routes_to_od_matrix task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/pasubio_hourly.od 2>/dev/null || true
rm -f /home/ga/SUMO_Output/peak_od_pair.txt 2>/dev/null || true
chown -R ga:ga /home/ga/SUMO_Output

# Verify the scenario data exists
if [ ! -f "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio.rou.xml" ]; then
    echo "ERROR: Scenario data missing!"
    exit 1
fi

# Start a terminal for the user
echo "Starting terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 4

# Focus and maximize the terminal window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="