#!/bin/bash
# Setup script for openvsp_wave_drag_area_ruling task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_wave_drag_area_ruling ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy clean eCRM-001 model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3" 2>/dev/null || \
    cp /opt/openvsp_models/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Calculate MD5 hash of original file to detect "do nothing" saves
md5sum "$MODELS_DIR/eCRM-001_wing_tail.vsp3" | awk '{print $1}' > /tmp/original_model_hash.txt

# Remove any stale outputs
rm -f /home/ga/Desktop/wave_drag_report.txt
rm -f "$MODELS_DIR/eCRM-001_wave_drag.vsp3"
rm -f /tmp/wave_drag_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the eCRM-001 model
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

echo "=== Setup complete: eCRM-001 ready for Wave Drag analysis ==="