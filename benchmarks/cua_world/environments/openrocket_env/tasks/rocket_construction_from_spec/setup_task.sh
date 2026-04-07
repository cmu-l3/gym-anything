#!/bin/bash
# Setup script for rocket_construction_from_spec task
# Starts OpenRocket with a blank slate.

echo "=== Setting up rocket_construction_from_spec task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

# Create directories and ensure correct permissions
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure the target file does NOT exist so the agent must create it
rm -f "$ROCKETS_DIR/phoenix_scout.ork" 2>/dev/null || true

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances to guarantee clean state
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket WITHOUT a file argument so it opens a blank new design
launch_openrocket ""
sleep 3

# Wait for application window to appear
wait_for_openrocket 90
sleep 3

# Focus and maximize window
focus_openrocket_window
sleep 2

# Dismiss any update/startup dialogs
dismiss_dialogs 3

# Take initial screenshot showing blank slate
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved. Task setup complete."
echo "=== rocket_construction_from_spec task setup complete ==="