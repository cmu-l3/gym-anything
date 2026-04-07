#!/bin/bash
# Setup script for openvsp_degengeom_analysis task
# Prepares eCRM-001 model, clears old outputs, launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_degengeom_analysis ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Kill any running OpenVSP
kill_openvsp

# Clear stale outputs
rm -f "$EXPORTS_DIR/eCRM001_degengeom.csv"
# Also clear any .csv DegenGeom files that may have been generated in the models dir
find "$MODELS_DIR" -name "*DegenGeom*" -o -name "*degen*" 2>/dev/null | xargs rm -f 2>/dev/null || true

rm -f /home/ga/Desktop/degengeom_report.txt
rm -f /tmp/openvsp_degengeom_analysis_result.json

# Record task start timestamp
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

echo "=== Setup complete: eCRM-001 ready for Degen Geom analysis ==="
