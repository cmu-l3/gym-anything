#!/bin/bash
echo "=== Setting up airframe_splice_coupler_retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

# Ensure directories exist and have proper permissions
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Clean up any potential artifacts from previous runs
rm -f "$ROCKETS_DIR/spliced_airframe.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/splice_repair_report.txt" 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/splice_gt.txt

# Ensure OpenRocket is closed before starting
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the source file
launch_openrocket "$ROCKETS_DIR/simple_model_rocket.ork"
sleep 3

# Wait for the application window to appear and stabilize
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot of the starting state
take_screenshot /tmp/splice_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== airframe_splice_coupler_retrofit task setup complete ==="