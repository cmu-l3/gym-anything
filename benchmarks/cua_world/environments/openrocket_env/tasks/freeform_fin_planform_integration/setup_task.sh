#!/bin/bash
# Setup script for freeform_fin_planform_integration task

echo "=== Setting up freeform_fin_planform_integration task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
# If the source doesn't exist in workspace, try falling back to the standard examples path
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

TASK_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure clean state (remove any previously saved files)
rm -f "$ROCKETS_DIR/freeform_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/fin_integration_report.txt" 2>/dev/null || true

# Copy source .ork to task working file to reset state
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Record task start time for anti-gaming verification
echo "task_start_ts=$(date +%s)" > /tmp/fin_integration_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the starting rocket
launch_openrocket "$TASK_ORK"
sleep 3

# Wait for UI to stabilize and maximize window
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot showing starting state
take_screenshot /tmp/fin_integration_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== freeform_fin_planform_integration task setup complete ==="