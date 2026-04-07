#!/bin/bash
# Setup script for booster_reconstruction_downsize task
# Copies the base rocket and opens it for the agent

echo "=== Setting up booster_reconstruction_downsize task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
WORKING_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"

# Create required directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to the working directory
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$WORKING_ORK"
else
    # Fallback to downloading if not in workspace
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/Dual%20parachute%20deployment.ork" -O "$WORKING_ORK" || { echo "FATAL: Could not get source .ork"; exit 1; }
fi
chown ga:ga "$WORKING_ORK"

# Ensure clean slate for output files
rm -f "$ROCKETS_DIR/reconstructed_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/reconstruction_memo.txt" 2>/dev/null || true

# Record ground truth start time to prevent gaming
echo "task_start_ts=$(date +%s)" > /tmp/reconstruction_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the starting rocket
launch_openrocket "$WORKING_ORK"
sleep 3

# Wait for UI and focus
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence
take_screenshot /tmp/reconstruction_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== booster_reconstruction_downsize task setup complete ==="