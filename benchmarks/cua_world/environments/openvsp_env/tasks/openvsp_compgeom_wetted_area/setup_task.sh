#!/bin/bash
# Setup script for openvsp_compgeom_wetted_area task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_compgeom_wetted_area ==="

# Create necessary directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Terminate any running OpenVSP
kill_openvsp

# Clear stale outputs to prevent gaming
rm -f "$EXPORTS_DIR/eCRM001_compgeom_results.csv"
find "$MODELS_DIR" -name "*CompGeom*" -o -name "*compgeom*" 2>/dev/null | xargs rm -f 2>/dev/null || true
rm -f /home/ga/Desktop/wetted_area_report.txt
rm -f /tmp/openvsp_compgeom_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the model loaded
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="