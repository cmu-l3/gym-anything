#!/bin/bash
# Setup script for payload_bay_integration task

echo "=== Setting up payload_bay_integration task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
WORKSPACE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to workspace
cp "$SOURCE_ORK" "$WORKSPACE_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$WORKSPACE_ORK"

# Remove any previous artifacts
rm -f "$ROCKETS_DIR/payload_integrated_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/payload_report.txt" 2>/dev/null || true

# Record original MD5 and start time for anti-gaming checks
md5sum "$WORKSPACE_ORK" | awk '{print $1}' > /tmp/original_md5.txt
date +%s > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket
launch_openrocket "$WORKSPACE_ORK"
sleep 3

# Wait for UI and focus
wait_for_openrocket 60
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== payload_bay_integration task setup complete ==="