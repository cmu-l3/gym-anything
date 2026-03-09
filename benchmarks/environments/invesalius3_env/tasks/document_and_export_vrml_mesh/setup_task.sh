#!/bin/bash
# Setup script for document_and_export_vrml_mesh task

set -e
echo "=== Setting up document_and_export_vrml_mesh task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
VRML_FILE="$OUTPUT_DIR/legacy_skull.wrl"
INFO_FILE="$OUTPUT_DIR/mesh_info.txt"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
rm -f "$VRML_FILE" "$INFO_FILE"
chown -R ga:ga "$OUTPUT_DIR"

# Ensure Data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Reset InVesalius
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with DICOM pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for application window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    exit 1
fi
sleep 5

# Handle startup dialogs
dismiss_startup_dialogs
focus_invesalius || true

# Maximize window
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Target output: $VRML_FILE"
echo "Target info: $INFO_FILE"