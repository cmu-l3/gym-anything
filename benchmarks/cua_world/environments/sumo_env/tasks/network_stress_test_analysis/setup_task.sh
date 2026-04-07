#!/bin/bash
echo "=== Setting up network_stress_test_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up output directory to ensure a fresh state
rm -f /home/ga/SUMO_Output/baseline_summary.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Output/stress_summary.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Output/stress_test_report.txt 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

# Make sure no SUMO processes are running
kill_sumo
sleep 1

# Open a terminal window for the user
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 3

# Wait for terminal to appear and maximize it
wait_for_window "Terminal" 10
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="