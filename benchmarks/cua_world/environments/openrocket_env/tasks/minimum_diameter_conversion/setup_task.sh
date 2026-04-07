#!/bin/bash
echo "=== Setting up minimum_diameter_conversion task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
TARGET_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$TARGET_ORK"
else
    # Fallback to downloading if workspace mapping failed
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/Dual%20parachute%20deployment.ork" -O "$TARGET_ORK"
fi

if [ ! -f "$TARGET_ORK" ]; then
    echo "FATAL: Could not copy or download source .ork"
    exit 1
fi

chown ga:ga "$TARGET_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/minimum_diameter.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/min_diameter_report.txt" 2>/dev/null || true

# Record task start time (for anti-gaming checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the original rocket
launch_openrocket "$TARGET_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== minimum_diameter_conversion task setup complete ==="