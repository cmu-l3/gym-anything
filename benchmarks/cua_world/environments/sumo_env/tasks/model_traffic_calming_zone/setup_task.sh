#!/bin/bash
echo "=== Setting up model_traffic_calming_zone task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure fresh output directory
rm -rf /home/ga/SUMO_Output/* 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Make sure the scenario directory is intact
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_acosta

# Launch a terminal for the agent to work in
echo "Launching terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"
    sleep 3
fi

# Focus and maximize the terminal
focus_and_maximize "Terminal"
sleep 1

# Take initial screenshot showing the terminal ready
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="