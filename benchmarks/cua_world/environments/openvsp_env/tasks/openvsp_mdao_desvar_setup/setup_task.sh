#!/bin/bash
# Setup script for openvsp_mdao_desvar_setup task
# Prepares the eCRM-001 model and clears any stale output files

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_mdao_desvar_setup ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any stale output files
rm -f "$MODELS_DIR/eCRM001_mdao.vsp3"
rm -f "/home/ga/Desktop/desvar_summary.txt"
rm -f /tmp/openvsp_mdao_desvar_setup_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
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

echo "=== Setup complete: eCRM-001 ready for MDAO desvar configuration ==="