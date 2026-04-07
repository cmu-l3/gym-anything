#!/bin/bash
echo "=== Setting up relocate_bus_stop_farside task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Clean up output directory to ensure a fresh state
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

# Prepare the scenario directory
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Ensure original scenario files are in place to prevent state bleed
cp /workspace/data/bologna_pasubio/pasubio_bus_stops.add.xml $SCENARIO_DIR/
cp /workspace/data/bologna_pasubio/pasubio_busses.rou.xml $SCENARIO_DIR/
cp /workspace/data/bologna_pasubio/run.sumocfg $SCENARIO_DIR/

# Create hidden backups for the verifier to diff against
cp $SCENARIO_DIR/pasubio_bus_stops.add.xml $SCENARIO_DIR/pasubio_bus_stops.add.xml.bak
cp $SCENARIO_DIR/pasubio_busses.rou.xml $SCENARIO_DIR/pasubio_busses.rou.xml.bak

# Fix permissions
chown -R ga:ga $SCENARIO_DIR

# Open a terminal for the user to work in (command-line workflow)
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$SCENARIO_DIR &"
sleep 2

# Maximize terminal for agent visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot showing clean workspace
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="