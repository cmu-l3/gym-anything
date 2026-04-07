#!/bin/bash
echo "=== Setting up mid_power_motor_upgrade_and_rebalance task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Start from clean state
rm -f "$ROCKETS_DIR/mid_power_upscale.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/upscale_report.txt" 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure simple_model_rocket.ork exists
if [ ! -f "$ROCKETS_DIR/simple_model_rocket.ork" ]; then
    cp /workspace/data/rockets/simple_model_rocket.ork "$ROCKETS_DIR/" 2>/dev/null || true
fi
chown ga:ga "$ROCKETS_DIR/simple_model_rocket.ork" 2>/dev/null || true

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket loaded
launch_openrocket "$ROCKETS_DIR/simple_model_rocket.ork"
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

echo "=== setup complete ==="