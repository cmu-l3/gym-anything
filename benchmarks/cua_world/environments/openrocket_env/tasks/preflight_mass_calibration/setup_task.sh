#!/bin/bash
# Setup script for preflight_mass_calibration task
# Loads the simple_model_rocket.ork design

echo "=== Setting up preflight_mass_calibration task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
WORKSPACE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure source file is present in the working directory
cp "$SOURCE_ORK" "$WORKSPACE_ORK" 2>/dev/null || true
if [ ! -f "$WORKSPACE_ORK" ]; then
    # Fallback to downloading it if not in workspace data
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/A%20simple%20model%20rocket.ork" -O "$WORKSPACE_ORK"
fi
chown ga:ga "$WORKSPACE_ORK"

# Remove any previous output files
rm -f "$ROCKETS_DIR/calibrated_simple_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/mass_properties_report.txt" 2>/dev/null || true

# Record ground truth start time
TASK_START_TS=$(date +%s)
echo "task_start_ts=$TASK_START_TS" > /tmp/mass_calibration_gt.txt

# Store MD5 of the original file to verify agent actually modified and saved it
ORIG_MD5=$(md5sum "$WORKSPACE_ORK" | awk '{print $1}')
echo "orig_md5=$ORIG_MD5" >> /tmp/mass_calibration_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the uncalibrated rocket
launch_openrocket "$WORKSPACE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/mass_calibration_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== preflight_mass_calibration task setup complete ==="