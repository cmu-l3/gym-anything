#!/bin/bash
echo "=== Setting up launch_guide_drag_penalty_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/two_stage_high_power_rocket.ork"
# Make sure the task file exists
if [ ! -f "$TASK_ORK" ]; then
    echo "Task file not found, copying from workspace data..."
    cp "/workspace/data/rockets/two_stage_high_power_rocket.ork" "$TASK_ORK" 2>/dev/null || true
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure clean state for output files
rm -f "$ROCKETS_DIR/guided_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/launch_guide_report.txt" 2>/dev/null || true

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/launch_guide_gt.txt

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
take_screenshot /tmp/launch_guide_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== launch_guide_drag_penalty_analysis task setup complete ==="