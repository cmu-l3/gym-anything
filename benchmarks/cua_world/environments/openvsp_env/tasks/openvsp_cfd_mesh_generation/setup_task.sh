#!/bin/bash
# Setup script for openvsp_cfd_mesh_generation task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_cfd_mesh_generation ==="

# Ensure directories exist and have proper permissions
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown -R ga:ga "$MODELS_DIR"
chown -R ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any stale output files the agent might create
rm -f "$EXPORTS_DIR/eCRM001_cfd_mesh.stl"
rm -f "$EXPORTS_DIR/eCRM001_cfd_mesh.msh"
rm -f /home/ga/Desktop/cfd_mesh_report.txt
rm -f /tmp/openvsp_cfd_mesh_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Wait for the OpenVSP window and focus it
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with eCRM-001 model."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete: model loaded and ready for meshing ==="