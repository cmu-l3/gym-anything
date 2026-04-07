#!/bin/bash
# Setup script for openvsp_three_view_drawing_export task
# Prepares the eCRM-001 model and clears any stale SVG export files

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_three_view_drawing_export ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"

# Copy real eCRM model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any stale output files
rm -f "$EXPORTS_DIR/eCRM001_top.svg"
rm -f "$EXPORTS_DIR/eCRM001_front.svg"
rm -f "$EXPORTS_DIR/eCRM001_side.svg"
rm -f /tmp/openvsp_three_view_drawing_export_result.json

# Kill any running OpenVSP instance to start clean
kill_openvsp

# Record task start timestamp for anti-gaming (ensures files were created DURING task)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Wait for application window to appear
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

echo "=== Setup complete: eCRM-001 is ready for export ==="