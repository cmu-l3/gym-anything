#!/bin/bash
echo "=== Setting up compute_emergency_isochrones task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure working directory exists and is clean
OUTPUT_DIR="/home/ga/SUMO_Output"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/isochrone_summary.txt" 2>/dev/null || true
rm -f "$OUTPUT_DIR/isochrone_selection.txt" 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_acosta/calculate_isochrone.py 2>/dev/null || true

chown -R ga:ga "$OUTPUT_DIR"

# Ensure no SUMO processes are running
kill_sumo

# Open a terminal for the agent in the scenario directory
echo "Opening terminal for agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"

# Wait for terminal window to appear
sleep 3
wait_for_window "Terminal" 10

# Maximize and focus terminal
focus_and_maximize "Terminal"
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="