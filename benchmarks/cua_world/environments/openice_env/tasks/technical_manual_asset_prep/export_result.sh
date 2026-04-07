#!/bin/bash
echo "=== Exporting Technical Manual Asset Prep result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File paths
FULL_CAPTURE="/home/ga/Desktop/full_screen_capture.png"
FINAL_ASSET="/home/ga/Desktop/fig_01_pleth_waveform.png"

# Check Full Capture
FULL_EXISTS="false"
FULL_MTIME=0
if [ -f "$FULL_CAPTURE" ]; then
    FULL_EXISTS="true"
    FULL_MTIME=$(stat -c %Y "$FULL_CAPTURE" 2>/dev/null || echo "0")
fi

# Check Final Asset
ASSET_EXISTS="false"
ASSET_MTIME=0
if [ -f "$FINAL_ASSET" ]; then
    ASSET_EXISTS="true"
    ASSET_MTIME=$(stat -c %Y "$FINAL_ASSET" 2>/dev/null || echo "0")
fi

# Check OpenICE Status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Check for Pulse Oximeter window
# Look for 'Pulse' or 'Oximeter' or 'SpO2' in window titles
PULSE_OX_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "Pulse|Oximeter|SpO2" > /dev/null; then
    PULSE_OX_RUNNING="true"
fi

# Create result JSON
# Note: We don't analyze image content here (bash is bad at that). 
# We export metadata and let verifier.py copy the actual images to analyze.
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "pulse_ox_running": $PULSE_OX_RUNNING,
    "full_capture_exists": $FULL_EXISTS,
    "full_capture_mtime": $FULL_MTIME,
    "final_asset_exists": $ASSET_EXISTS,
    "final_asset_mtime": $ASSET_MTIME,
    "full_capture_path": "$FULL_CAPTURE",
    "final_asset_path": "$FINAL_ASSET",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json