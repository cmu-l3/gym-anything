#!/bin/bash
# Setup script for tube_fin_conversion task

echo "=== Setting up tube_fin_conversion task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
WORKSPACE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
EXPORTS_DIR="/home/ga/Documents/exports"
ROCKETS_DIR="/home/ga/Documents/rockets"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure source ORK exists
if [ ! -f "$SOURCE_ORK" ]; then
    if [ -f "$WORKSPACE_ORK" ]; then
        cp "$WORKSPACE_ORK" "$SOURCE_ORK"
    else
        echo "Downloading simple_model_rocket.ork..."
        wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/A%20simple%20model%20rocket.ork" -O "$SOURCE_ORK"
    fi
fi
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Remove any previous task artifacts
rm -f "$ROCKETS_DIR/tube_fin_conversion.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/tube_fin_report.md" 2>/dev/null || true
rm -f "$EXPORTS_DIR/tube_fin_report.txt" 2>/dev/null || true

# Record ground truth and anti-gaming initial state
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_ts.txt
md5sum "$SOURCE_ORK" | awk '{print $1}' > /tmp/source_ork_md5.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline rocket
echo "Launching OpenRocket with baseline simple_model_rocket.ork..."
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/tube_fin_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== tube_fin_conversion task setup complete ==="