#!/bin/bash
# Setup script for export_skull_stl task

set -e
echo "=== Setting up export_skull_stl task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/skull_model.stl"

# Ensure output directory exists (owned by ga)
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output file to prevent false positives
rm -f "$OUTPUT_FILE"

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Close any existing InVesalius instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with DICOM pre-loaded
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window and settle
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record baseline: no STL file exists
echo "false" > /tmp/initial_stl_exists
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Output directory: $OUTPUT_DIR"
echo "Expected output: $OUTPUT_FILE"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
