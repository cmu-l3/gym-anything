#!/bin/bash
# Setup script for openvsp_parasite_drag_buildup task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_parasite_drag_buildup ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown -R ga:ga "$MODELS_DIR" "$EXPORTS_DIR" /home/ga/Desktop 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Kill any running OpenVSP
kill_openvsp

# Clear any stale outputs
rm -f "$EXPORTS_DIR/eCRM001_parasite_drag.csv"
rm -f /home/ga/Desktop/drag_report.txt
rm -f /tmp/openvsp_parasite_drag_result.json

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete: eCRM-001 ready for Parasite Drag analysis ==="