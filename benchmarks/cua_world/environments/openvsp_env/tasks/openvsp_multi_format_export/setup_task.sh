#!/bin/bash
# Setup script for openvsp_multi_format_export task
# Prepares the eCRM-001 model and clears any stale export files

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_multi_format_export ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"

# Copy model to working location (use canonical filename)
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any stale output files the agent might create
rm -f "$EXPORTS_DIR/eCRM001_mesh.stl"
rm -f "$EXPORTS_DIR/eCRM001_cart3d.tri"
rm -f "$EXPORTS_DIR/eCRM001_degengeom.csv"

# Kill any running OpenVSP instance
kill_openvsp

# Remove stale result file
rm -f /tmp/openvsp_multi_format_export_result.json

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

echo "=== Setup complete: exports directory is empty, model is ready ==="
