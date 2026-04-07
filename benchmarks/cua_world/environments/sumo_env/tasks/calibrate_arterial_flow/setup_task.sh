#!/bin/bash
set -e
echo "=== Setting up calibrate_arterial_flow task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Ensure directories exist
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any potential previous task artifacts
rm -f "$WORK_DIR/calibrator.add.xml" 2>/dev/null || true
rm -f "$OUTPUT_DIR/calibrator_log.xml" 2>/dev/null || true

# Backup and restore original sumocfg to ensure a clean state
if [ ! -f "$WORK_DIR/run.sumocfg.bak" ]; then
    cp "$WORK_DIR/run.sumocfg" "$WORK_DIR/run.sumocfg.bak"
else
    cp "$WORK_DIR/run.sumocfg.bak" "$WORK_DIR/run.sumocfg"
fi
chown ga:ga "$WORK_DIR/run.sumocfg"

# Wait for display and start a terminal for the user
sleep 2
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR &"
    sleep 3
fi

# Maximize and focus the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="