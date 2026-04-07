#!/bin/bash
echo "=== Setting up simulate_urban_freight_delivery task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Define working directories
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Ensure clean state (remove any artifacts from previous runs)
rm -f "$SCENARIO_DIR/pasubio_freight.rou.xml" 2>/dev/null || true
rm -f "$SCENARIO_DIR/tripinfos.xml" 2>/dev/null || true
rm -f "$OUTPUT_DIR/freight_report.txt" 2>/dev/null || true

# Restore original run.sumocfg to ensure a clean starting state
cp /workspace/data/bologna_pasubio/run.sumocfg "$SCENARIO_DIR/run.sumocfg"
chown ga:ga "$SCENARIO_DIR/run.sumocfg"

# Open a terminal for the user in the scenario directory
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$SCENARIO_DIR &"
sleep 2

# Maximize the terminal for better visibility
focus_and_maximize "Terminal"
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="