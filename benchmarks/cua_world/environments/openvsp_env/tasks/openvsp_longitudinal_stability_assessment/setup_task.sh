#!/bin/bash
# Setup script for openvsp_longitudinal_stability_assessment task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_longitudinal_stability_assessment ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy eCRM model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Kill any running OpenVSP
kill_openvsp

# Remove stale VSPAero output directories and files
VSPAERO_DIR="$MODELS_DIR/vspaero"
rm -rf "$VSPAERO_DIR" 2>/dev/null || true
# Clear any polar files from the working directory
find "$MODELS_DIR" -name "*.polar" -o -name "*.lod" -o -name "*.history" -o -name "*.adb" 2>/dev/null | xargs rm -f 2>/dev/null || true

# Remove stale report and target save files
rm -f /home/ga/Desktop/stability_report.txt
rm -f "$MODELS_DIR/eCRM-001_stability.vsp3"
rm -f /tmp/openvsp_stability_result.json

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

echo "=== Setup complete: eCRM-001 ready ==="