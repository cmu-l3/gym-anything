#!/bin/bash
# Setup script for simulate_bone_loss_erosion task

set -e
echo "=== Setting up simulate_bone_loss_erosion task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/bone_loss_simulation.inv3"

# Ensure output directory exists and is empty of target file
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true
rm -f "$OUTPUT_FILE"

# Verify DICOM data
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Clean up previous instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Launch InVesalius with data
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for application window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 5

# Handle startup dialogs and window management
dismiss_startup_dialogs
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="