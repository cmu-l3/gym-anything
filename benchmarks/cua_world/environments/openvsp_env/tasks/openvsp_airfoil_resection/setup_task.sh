#!/bin/bash
# Setup script for openvsp_airfoil_resection task
# Prepares eCRM-001 model, clears old outputs, launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_airfoil_resection ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
chown ga:ga "$MODELS_DIR" 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any pre-existing output
rm -f "$MODELS_DIR/eCRM001_resectioned.vsp3"
rm -f /tmp/openvsp_airfoil_resection_result.json

# Record original md5 hash to detect if agent just copies the file without changes
md5sum "$MODELS_DIR/eCRM-001_wing_tail.vsp3" | awk '{print $1}' > /tmp/original_md5.txt

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Kill any running OpenVSP
kill_openvsp

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

echo "=== Setup complete: eCRM-001 ready for airfoil resectioning ==="