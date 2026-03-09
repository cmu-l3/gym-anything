#!/bin/bash
echo "=== Setting up export_stl_mesh task ==="

source /workspace/scripts/task_utils.sh

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"

# Remove any previous export output
rm -f "$EXPORTS_DIR/eCRM_export.stl" 2>/dev/null || true

# Validate source file exists
SOURCE_FILE="/opt/openvsp_models/eCRM-001_wing_tail.vsp3"
if [ ! -f "$SOURCE_FILE" ]; then
    SOURCE_FILE="/workspace/data/eCRM-001_wing_tail.vsp3"
fi

if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERROR: eCRM-001_wing_tail.vsp3 not found"
    exit 1
fi

# Copy a fresh copy of the model to the working directory
cp "$SOURCE_FILE" "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chown ga:ga "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chown ga:ga "$EXPORTS_DIR"

# Kill any existing OpenVSP instances
kill_openvsp

# Launch OpenVSP with the eCRM model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

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
take_screenshot /tmp/export_stl_mesh_start.png

echo "=== export_stl_mesh task setup complete ==="
echo "Goal: Export the eCRM-001 model as STL to /home/ga/Documents/OpenVSP/exports/eCRM_export.stl"
