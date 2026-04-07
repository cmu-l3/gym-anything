#!/bin/bash
# Setup script for two_stage_booster_retrofit task

echo "=== Setting up two_stage_booster_retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure the source file exists (fallback to workspace data)
if [ ! -f "$SOURCE_ORK" ]; then
    echo "WARNING: simple_model_rocket.ork not found. Copying from workspace data..."
    cp /workspace/data/rockets/simple_model_rocket.ork "$SOURCE_ORK" 2>/dev/null || true
    chown ga:ga "$SOURCE_ORK"
fi

# Remove previous output files to ensure a clean state
rm -f "$ROCKETS_DIR/two_stage_upgrade.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/staging_report.txt" 2>/dev/null || true

# Record ground truth start time for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/two_stage_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the source single-stage rocket
launch_openrocket "$SOURCE_ORK"
sleep 3

# Wait for and maximize window
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/two_stage_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== two_stage_booster_retrofit task setup complete ==="