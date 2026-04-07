#!/bin/bash
# Setup script for openvsp_vtail_butterfly_config task
# Prepares the eCRM-001 model and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_vtail_butterfly_config ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any stale output files from previous attempts
rm -f "$MODELS_DIR/eCRM001_vtail_study.vsp3"
rm -f /tmp/openvsp_vtail_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Kill any running OpenVSP instances for a clean start
kill_openvsp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Wait for application window
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with eCRM-001 model."
else
    echo "WARNING: OpenVSP window did not appear in time. Agent may need to launch it."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="