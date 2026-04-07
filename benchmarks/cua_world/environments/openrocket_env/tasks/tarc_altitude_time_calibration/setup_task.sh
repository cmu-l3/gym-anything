#!/bin/bash
# Setup script for tarc_altitude_time_calibration task
# Copies simple_model_rocket.ork to use as the base for TARC tuning

echo "=== Setting up tarc_altitude_time_calibration task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
BASE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to standard location
cp "$SOURCE_ORK" "$BASE_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$BASE_ORK"

# Clean old artifacts if they exist
rm -f "$ROCKETS_DIR/tarc_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/tarc_report.txt" 2>/dev/null || true

# Record ground truth start time
echo "task_start_ts=$(date +%s)" > /tmp/tarc_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base model rocket
launch_openrocket "$BASE_ORK"
sleep 3

# Wait for UI and focus
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/tarc_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== tarc_altitude_time_calibration task setup complete ==="