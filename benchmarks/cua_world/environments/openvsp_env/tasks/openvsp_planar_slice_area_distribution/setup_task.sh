#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Planar Slice Area Distribution task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean previous results and create required directories
rm -f /home/ga/Desktop/area_ruling_report.txt
rm -rf /home/ga/Documents/OpenVSP/exports
mkdir -p /home/ga/Documents/OpenVSP/exports

# Ensure the real eCRM-001 model exists in the working directory
MODEL_FILE="/home/ga/Documents/OpenVSP/eCRM-001_wing_tail.vsp3"
if [ ! -f "$MODEL_FILE" ]; then
    for src in /opt/openvsp_models/eCRM-001_wing_tail.vsp3 /workspace/data/eCRM-001_wing_tail.vsp3; do
        if [ -f "$src" ]; then
            cp "$src" "$MODEL_FILE"
            break
        fi
    done
fi

if [ ! -f "$MODEL_FILE" ]; then
    echo "ERROR: eCRM-001 model not found in environment."
    exit 1
fi

# Set permissions
chown -R ga:ga /home/ga/Documents/OpenVSP
chown -R ga:ga /home/ga/Desktop

# Kill any existing OpenVSP instance to ensure a clean state
kill_openvsp
sleep 2

# Clean up any stale slice output files from previous runs
find /home/ga/Documents/OpenVSP -type f -name "*.slc" -delete 2>/dev/null || true
find /home/ga/Documents/OpenVSP -type f -name "*PlanarSlice*" -delete 2>/dev/null || true

# Launch OpenVSP with the eCRM model
launch_openvsp "$MODEL_FILE"

# Wait for window, focus, and maximize
WID=$(wait_for_openvsp 90)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    # Take initial screenshot showing the eCRM model loaded
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully with eCRM-001 model."
else
    echo "WARNING: OpenVSP did not start in time."
fi

echo "=== Planar Slice task setup complete ==="