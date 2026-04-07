#!/bin/bash
echo "=== Setting up simulate_motorcycle_lane_splitting task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure SUMO is not already running
kill_sumo

# Define working directory
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Ensure directories exist and are clean of previous artifacts
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

rm -f "${WORK_DIR}/motorcycles.rou.xml" 2>/dev/null || true
rm -f "${WORK_DIR}/run_sublane.sumocfg" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/sublane_tripinfos.xml" 2>/dev/null || true
rm -f "${OUTPUT_DIR}/mode_comparison.txt" 2>/dev/null || true

# Launch terminal for the agent in the working directory
echo "Starting Terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=${WORK_DIR} &"
sleep 3

# Wait for terminal to appear and maximize it
wait_for_window "Terminal" 10
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="