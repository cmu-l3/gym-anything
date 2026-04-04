#!/bin/bash
# Setup script for export_model_and_picture task

set -e
echo "=== Setting up export_model_and_picture task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files
rm -f "$OUTPUT_DIR/skull_surface.obj"
rm -f "$OUTPUT_DIR/surgical_view.png"

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

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

# Baseline: neither output file exists
echo "false" > /tmp/initial_obj_exists
echo "false" > /tmp/initial_png_exists
date +%s > /tmp/task_start_timestamp

take_screenshot /tmp/task_start.png

echo "Expected OBJ: $OUTPUT_DIR/skull_surface.obj"
echo "Expected PNG: $OUTPUT_DIR/surgical_view.png"
echo "=== Setup Complete ==="
