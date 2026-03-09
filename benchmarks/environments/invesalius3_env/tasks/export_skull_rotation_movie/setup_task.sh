#!/bin/bash
# Setup script for export_skull_rotation_movie task

set -e
echo "=== Setting up export_skull_rotation_movie task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
FRAMES_DIR="/home/ga/Documents/skull_rotation_frames"
VIDEO_PATH="/home/ga/Documents/skull_rotation.avi"

# Clean up previous outputs
rm -rf "$FRAMES_DIR"
rm -f "$VIDEO_PATH"
mkdir -p "$FRAMES_DIR"
# Ensure directory exists but is empty
rm -rf "$FRAMES_DIR"/*
# Fix permissions
chown -R ga:ga "/home/ga/Documents"

# Ensure DICOM data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Close existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

# Maximize
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming (file creation check)
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Setup complete. Output expected at $FRAMES_DIR or $VIDEO_PATH"