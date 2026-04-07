#!/bin/bash
echo "=== Setting up streamer_recovery_conversion task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure clean state (remove potentially existing outputs)
rm -f "$ROCKETS_DIR/streamer_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/streamer_report.txt" 2>/dev/null || true

# Record ground truth and timestamp for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/streamer_task_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket loaded
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence
take_screenshot /tmp/streamer_task_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== streamer_recovery_conversion task setup complete ==="