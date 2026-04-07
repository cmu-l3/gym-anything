#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_component_buildup_sets ==="

mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"

# Copy base model to working location
cp /opt/openvsp_models/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3" 2>/dev/null || \
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3" 2>/dev/null || true
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3" 2>/dev/null || true

# Remove any stale output file from previous runs
rm -f "$EXPORTS_DIR/eCRM-001_sets.vsp3"
rm -f /tmp/openvsp_sets_result.json

kill_openvsp

# Record task start timestamp for anti-gaming verification
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
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="