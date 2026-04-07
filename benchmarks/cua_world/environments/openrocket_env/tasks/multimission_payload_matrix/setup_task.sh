#!/bin/bash
echo "=== Setting up multimission_payload_matrix task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
# Fallback to installed dir if not in workspace
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/home/ga/Documents/rockets/dual_parachute_deployment.ork"
fi

# Ensure directories exist
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Clean up any artifacts from previous runs
rm -f "$ROCKETS_DIR/multimission_payload.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/mission_matrix_report.txt" 2>/dev/null || true

# Record task start time
echo "task_start_ts=$(date +%s)" > /tmp/multimission_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket directly with the source rocket (agent must "Save As")
echo "Launching OpenRocket with base design..."
launch_openrocket "$SOURCE_ORK"
sleep 3

# Wait for UI and setup window
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== multimission_payload_matrix task setup complete ==="