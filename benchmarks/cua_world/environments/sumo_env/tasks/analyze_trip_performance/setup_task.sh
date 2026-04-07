#!/bin/bash
echo "=== Setting up analyze_trip_performance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any existing outputs to ensure a fresh start
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/tripinfos.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/sumo_log.txt 2>/dev/null || true
rm -f /home/ga/SUMO_Output/trip_report.txt 2>/dev/null || true

# Ensure output directory exists and is owned by ga
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Scenarios

# Ensure no SUMO processes are lingering
kill_sumo
sleep 1

# Open a terminal for the user, as this task heavily relies on CLI
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 3

# Wait for terminal and focus it
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="