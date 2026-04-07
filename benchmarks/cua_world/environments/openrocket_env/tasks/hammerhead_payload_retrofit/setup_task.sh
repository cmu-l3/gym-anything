#!/bin/bash
echo "=== Setting up hammerhead_payload_retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

ROCKETS_DIR="/home/ga/Documents/rockets"
EXPORTS_DIR="/home/ga/Documents/exports"
TASK_ORK_BASE="$ROCKETS_DIR/hammerhead_base.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$TASK_ORK_BASE"
elif [ -f "$ROCKETS_DIR/simple_model_rocket.ork" ]; then
    cp "$ROCKETS_DIR/simple_model_rocket.ork" "$TASK_ORK_BASE"
else
    echo "FATAL: Could not find base rocket file simple_model_rocket.ork"
    exit 1
fi
chown ga:ga "$TASK_ORK_BASE"

# Ensure output files from a previous run are deleted
rm -f "$ROCKETS_DIR/hammerhead_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/hammerhead_report.txt" 2>/dev/null || true

# Record ground truth start time
echo "task_start_ts=$(date +%s)" > /tmp/hammerhead_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket loaded
launch_openrocket "$TASK_ORK_BASE"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/hammerhead_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== hammerhead_payload_retrofit task setup complete ==="