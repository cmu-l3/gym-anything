#!/bin/bash
echo "=== Setting up model_traffic_incident task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing SUMO processes just in case
kill_sumo
sleep 1

# Clean previous outputs and target files to ensure a clean state
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUT_DIR="/home/ga/SUMO_Output"

rm -f "${SCENARIO_DIR}/incident.rou.xml"
rm -f "${SCENARIO_DIR}/run_incident.sumocfg"
rm -rf "${OUT_DIR}/*"
mkdir -p "$OUT_DIR"
chown ga:ga "$OUT_DIR"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Start a terminal for the agent (this task is heavily terminal-based)
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=${SCENARIO_DIR} &"

# Wait for the terminal to launch and maximize it
sleep 3
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="