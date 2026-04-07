#!/bin/bash
echo "=== Setting up fabrication_blueprint_export task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
BASE_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"
TARGET_ORK="$ROCKETS_DIR/manufacturing_ready.ork"
TARGET_PDF="$EXPORTS_DIR/manufacturing_blueprints.pdf"

# Create required directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure starting file exists
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$BASE_ORK"
else
    # Fallback to the one downloaded in install script
    cp "/home/ga/Documents/rockets/dual_parachute_deployment.ork" "$BASE_ORK" 2>/dev/null || true
fi
chown ga:ga "$BASE_ORK"

# Clean up any previous attempts
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "$TARGET_PDF" 2>/dev/null || true

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/fabrication_task_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket
launch_openrocket "$BASE_ORK"
sleep 3

# Wait for UI to initialize and maximize it
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence
take_screenshot /tmp/fabrication_task_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== fabrication_blueprint_export task setup complete ==="