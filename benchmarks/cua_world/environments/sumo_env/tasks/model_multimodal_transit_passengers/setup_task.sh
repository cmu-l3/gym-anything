#!/bin/bash
echo "=== Setting up model_multimodal_transit_passengers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
sudo -u ga mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/personinfo.xml 2>/dev/null || true

# Clean up any previously created pedestrian files
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
rm -f "$WORK_DIR/pedestrians.rou.xml" 2>/dev/null || true

# Backup the original config file to ensure clean state and comparison
if [ ! -f "$WORK_DIR/run.sumocfg.bak" ]; then
    cp "$WORK_DIR/run.sumocfg" "$WORK_DIR/run.sumocfg.bak"
    chown ga:ga "$WORK_DIR/run.sumocfg.bak"
else
    # Restore from backup
    cp "$WORK_DIR/run.sumocfg.bak" "$WORK_DIR/run.sumocfg"
    chown ga:ga "$WORK_DIR/run.sumocfg"
fi

# Ensure no SUMO processes are lingering
kill_sumo
sleep 1

# Open a terminal for the user to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR &"
    sleep 3
fi

# Maximize the terminal
focus_and_maximize "Terminal" 2>/dev/null || true

# Take initial screenshot of desktop state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="