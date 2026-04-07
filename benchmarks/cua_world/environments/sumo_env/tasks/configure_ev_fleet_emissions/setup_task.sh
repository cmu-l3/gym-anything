#!/bin/bash
echo "=== Setting up Configure EV Fleet Emissions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create/ensure directories exist with proper permissions
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"

# Clean up any potential artifacts from previous attempts
rm -f "$WORK_DIR/ev_vtypes.add.xml" 2>/dev/null
rm -f "$WORK_DIR/acosta_fleet.rou.xml" 2>/dev/null
rm -f "$WORK_DIR/ev_run.sumocfg" 2>/dev/null
rm -f "/home/ga/SUMO_Output/emissions.xml" 2>/dev/null
rm -f "/home/ga/SUMO_Output/ev_tripinfo.xml" 2>/dev/null
rm -f "/home/ga/SUMO_Output/ev_fleet_report.txt" 2>/dev/null

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR &"
    sleep 3
fi

# Wait for window and maximize
wait_for_window "Terminal" 10
focus_and_maximize "Terminal"

# Take screenshot of initial state (for evidence)
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "The agent must create configuration files, run SUMO, and analyze emissions."