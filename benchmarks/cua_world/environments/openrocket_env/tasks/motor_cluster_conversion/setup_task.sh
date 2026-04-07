#!/bin/bash
# Setup script for motor_cluster_conversion task

echo "=== Setting up motor_cluster_conversion task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
WORKSPACE_BACKUP="/workspace/data/rockets/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure source file exists (copy from workspace if missing)
if [ ! -f "$SOURCE_ORK" ]; then
    if [ -f "$WORKSPACE_BACKUP" ]; then
        cp "$WORKSPACE_BACKUP" "$SOURCE_ORK"
    else
        echo "FATAL: simple_model_rocket.ork not found anywhere!"
        exit 1
    fi
fi
chown ga:ga "$SOURCE_ORK"

# Remove any previous output files
rm -f "$ROCKETS_DIR/cluster_conversion.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/cluster_report.txt" 2>/dev/null || true

# Record ground truth and anti-gaming initial state
BASE_MD5=$(md5sum "$SOURCE_ORK" | awk '{print $1}')
echo "base_md5=$BASE_MD5" > /tmp/cluster_gt.txt
echo "task_start_ts=$(date +%s)" >> /tmp/cluster_gt.txt

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

# Take initial screenshot to document starting state
take_screenshot /tmp/cluster_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== motor_cluster_conversion task setup complete ==="