#!/bin/bash
echo "=== Setting up motor adapter downsize retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/janus_38mm.ork"

# Ensure directories exist
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Clean up previous outputs
rm -f "$ROCKETS_DIR/janus_29mm_adapter.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/adapter_report.txt" 2>/dev/null || true

# Check if source exists, if not try to copy from workspace
if [ ! -f "$SOURCE_ORK" ]; then
    cp "/workspace/data/rockets/janus_38mm.ork" "$SOURCE_ORK" 2>/dev/null || true
    chown ga:ga "$SOURCE_ORK"
fi

# Record ground truth start time
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the source rocket
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== Setup complete ==="