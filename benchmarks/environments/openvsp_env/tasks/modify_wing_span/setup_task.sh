#!/bin/bash
echo "=== Setting up modify_wing_span task ==="

source /workspace/scripts/task_utils.sh

# Ensure working directory exists
mkdir -p "$MODELS_DIR"

# Validate source file exists
SOURCE_FILE="/opt/openvsp_models/Cessna-210_metric.vsp3"
if [ ! -f "$SOURCE_FILE" ]; then
    SOURCE_FILE="/workspace/data/Cessna-210_metric.vsp3"
fi

if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERROR: Cessna-210_metric.vsp3 not found"
    exit 1
fi

# Copy a fresh copy of the model to the working directory
cp "$SOURCE_FILE" "$MODELS_DIR/Cessna-210_metric.vsp3"
chown ga:ga "$MODELS_DIR/Cessna-210_metric.vsp3"

# Record initial file hash for delta verification
md5sum "$MODELS_DIR/Cessna-210_metric.vsp3" | awk '{print $1}' > /tmp/initial_model_md5.txt

# Kill any existing OpenVSP instances
kill_openvsp

# Launch OpenVSP with the Cessna model
launch_openvsp "$MODELS_DIR/Cessna-210_metric.vsp3"

# Wait for window
WID=$(wait_for_openvsp 60)
if [ -z "$WID" ]; then
    echo "ERROR: OpenVSP window did not appear"
    exit 1
fi
echo "OpenVSP window appeared: $WID"

sleep 3

# Dismiss any dialogs
dismiss_dialogs 2

# Focus and maximize
focus_openvsp
sleep 2

# Take screenshot to verify start state
take_screenshot /tmp/modify_wing_span_start.png

echo "=== modify_wing_span task setup complete ==="
echo "Goal: Change the wing span from ~11.2m to exactly 14.0m and save the file."
