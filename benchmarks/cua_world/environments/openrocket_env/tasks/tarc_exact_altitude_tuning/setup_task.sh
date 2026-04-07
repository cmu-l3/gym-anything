#!/bin/bash
echo "=== Setting up tarc_exact_altitude_tuning task ==="

# Source utilities
source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure working directories exist
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure the base rocket is available (from data volumes) and ensure a clean slate
cp /workspace/data/rockets/simple_model_rocket.ork "$ROCKETS_DIR/simple_model_rocket.ork" 2>/dev/null || true
chown ga:ga "$ROCKETS_DIR/simple_model_rocket.ork"

# Remove any previous artifacts
rm -f "$ROCKETS_DIR/tuned_altitude_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/ballast_tuning_report.txt" 2>/dev/null || true

# Kill any existing OpenRocket instances to ensure a clean start
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline simple rocket design
echo "Launching OpenRocket..."
launch_openrocket "$ROCKETS_DIR/simple_model_rocket.ork"
sleep 3

# Wait for application window to open and stabilize
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2

# Dismiss any potential update/tip dialogs
dismiss_dialogs 3

# Take an initial state screenshot as evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved. Setup complete."