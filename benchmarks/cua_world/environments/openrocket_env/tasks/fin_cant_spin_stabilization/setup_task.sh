#!/bin/bash
# Setup script for fin_cant_spin_stabilization task

echo "=== Setting up fin_cant_spin_stabilization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
# Fallback if not found in workspace data mount
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
fi

# Ensure working directories exist
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Clean up any potential artifacts from previous runs
rm -f "$ROCKETS_DIR/spin_stabilized_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/spin_stabilization_report.txt" 2>/dev/null || true

# Record task start time for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/fin_cant_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline simple_model_rocket.ork
echo "Launching OpenRocket..."
launch_openrocket "$SOURCE_ORK"
sleep 3

# Wait for UI to load and become active
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take an initial screenshot to document the starting state
take_screenshot /tmp/fin_cant_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== fin_cant_spin_stabilization task setup complete ==="