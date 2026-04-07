#!/bin/bash
echo "=== Setting up implement_new_bus_stop task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamps)
date +%s > /tmp/task_start_time.txt

# Ensure SUMO is not already running
kill_sumo
sleep 1

# Define workspace directories
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUT_DIR="/home/ga/SUMO_Output"

# Clean up output directory to ensure a fresh state
rm -rf "$OUT_DIR"/* 2>/dev/null || true
mkdir -p "$OUT_DIR"
chown ga:ga "$OUT_DIR"

# Restore Pasubio scenario files to pristine condition just in case
if [ -d "/workspace/data/bologna_pasubio" ]; then
    cp -r /workspace/data/bologna_pasubio/* "$WORK_DIR/"
    chown -R ga:ga "$WORK_DIR"
fi

# Make sure basic gui-settings reference is present if missing from base data
if ! grep -q "gui-settings-file" "$WORK_DIR/run.sumocfg"; then
    sed -i '/<\/sumoConfiguration>/i \    <gui_only>\n        <gui-settings-file value="settings.gui.xml"/>\n    </gui_only>' "$WORK_DIR/run.sumocfg"
fi

# Open a terminal for the user to start working from
echo "Starting terminal in working directory..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR &"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="