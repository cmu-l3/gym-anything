#!/bin/bash
# Setup script for clustered_motor_failure_fmea task

echo "=== Setting up clustered_motor_failure_fmea task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/clustered_motors.ork"
BASE_ORK="$ROCKETS_DIR/clustered_motors.ork"
TARGET_ORK="$ROCKETS_DIR/clustered_fmea.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to the base file
# Use cp -f to overwrite if exists
if [ -f "$SOURCE_ORK" ]; then
    cp -f "$SOURCE_ORK" "$BASE_ORK"
else
    # Fallback to downloading if workspace data is missing
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/Clustered%20motors.ork" -O "$BASE_ORK" || { echo "FATAL: Could not get source .ork"; exit 1; }
fi
chown ga:ga "$BASE_ORK"

# Remove target file and report if they exist from previous runs
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "$EXPORTS_DIR/fmea_report.txt" 2>/dev/null || true

# Record ground truth and timestamp for anti-gaming
echo "task_start_ts=$(date +%s)" > /tmp/fmea_task_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket
launch_openrocket "$BASE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/fmea_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== clustered_motor_failure_fmea task setup complete ==="