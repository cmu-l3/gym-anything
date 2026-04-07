#!/bin/bash
echo "=== Setting up Add Pedestrian Sidewalks Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running SUMO processes
kill_sumo

# Ensure output directory exists and is completely clean
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Verify scenario files are in place
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
if [ ! -f "$SCENARIO_DIR/pasubio_buslanes.net.xml" ]; then
    echo "ERROR: Pasubio network file not found!"
    exit 1
fi
if [ ! -f "$SCENARIO_DIR/pasubio.rou.xml" ]; then
    echo "ERROR: Pasubio route file not found!"
    exit 1
fi
if [ ! -f "$SCENARIO_DIR/pasubio_vtypes.add.xml" ]; then
    echo "ERROR: Pasubio vehicle types file not found!"
    exit 1
fi

echo "Scenario files verified at: $SCENARIO_DIR"

# Ensure SUMO tools are accessible
export SUMO_HOME="/usr/share/sumo"
if ! command -v netconvert &> /dev/null; then
    echo "ERROR: netconvert not found in PATH"
    exit 1
fi
if ! command -v sumo &> /dev/null; then
    echo "ERROR: sumo not found in PATH"
    exit 1
fi
echo "SUMO tools verified: netconvert and sumo available"

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 bash -c '
    # Open gnome-terminal maximized
    gnome-terminal --maximize --working-directory=/home/ga/SUMO_Output &
'" 2>/dev/null || true

# Wait for terminal to appear
sleep 3
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Pedestrian sidewalks task setup complete ==="
echo "Scenario directory: $SCENARIO_DIR"
echo "Output directory: /home/ga/SUMO_Output/"