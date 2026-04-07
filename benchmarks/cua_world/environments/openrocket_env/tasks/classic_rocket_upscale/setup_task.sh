#!/bin/bash
# Setup script for classic_rocket_upscale task

echo "=== Setting up classic_rocket_upscale task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

if [ -f "/workspace/data/rockets/simple_model_rocket.ork" ]; then
    SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
else
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

TASK_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Ensure we have a clean copy if it was modified
if [ "$SOURCE_ORK" != "$TASK_ORK" ] && [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$TASK_ORK"
fi
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/upscaled_2x.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/upscale_report.txt" 2>/dev/null || true

# Record ground truth timestamp
echo "task_start_ts=$(date +%s)" > /tmp/upscale_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the clean rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/upscale_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== classic_rocket_upscale task setup complete ==="