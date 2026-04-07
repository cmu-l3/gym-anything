#!/bin/bash
# Setup script for openvsp_wake_downwash_penalty task
# Prepares the baseline eCRM-001 model and clears any stale outputs

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_wake_downwash_penalty ==="

mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Clear old output files to prevent false positives
rm -f "$MODELS_DIR/tandem_wake.vsp3"
rm -f /home/ga/Desktop/wake_penalty_report.txt
rm -rf "$MODELS_DIR/vspaero" 2>/dev/null || true
find "$MODELS_DIR" -name "*.polar" -o -name "*.history" 2>/dev/null | xargs rm -f 2>/dev/null || true

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming checks
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
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="