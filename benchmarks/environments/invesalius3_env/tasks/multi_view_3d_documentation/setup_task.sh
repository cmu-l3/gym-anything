#!/bin/bash
# Setup script for multi_view_3d_documentation task

set -e
echo "=== Setting up multi_view_3d_documentation task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents/surgical_views"

# Ensure output directory exists (owned by ga)
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files to prevent false positives
rm -f "$OUTPUT_DIR/anterior_view.png"
rm -f "$OUTPUT_DIR/lateral_view.png"
rm -f "$OUTPUT_DIR/superior_view.png"
rm -f "$OUTPUT_DIR/skull_study.inv3"

# Create imaging protocol document to differentiate this task's starting state
cat > "/home/ga/Documents/imaging_protocol.txt" << 'PROTOCOL'
PRE-OPERATIVE IMAGING PROTOCOL — NEUROSURGERY
===============================================
Case: Cranial CT Reconstruction Documentation
Data: CT Cranium series (ct_cranium/0051)

Required 3D View Captures (save to /home/ga/Documents/surgical_views/):
  1. anterior_view.png  — Frontal/anterior face of skull (normed anterior view)
  2. lateral_view.png   — Left lateral profile (patient's left side facing viewer)
  3. superior_view.png  — Cranial vertex top-down view (superior projection)

Required Measurements (minimum 3, place on CT slice views):
  - At least one transverse (left-right) cranial diameter measurement
  - At least one anteroposterior (front-back) cranial diameter measurement
  - At least one additional dimension measurement

Project Output:
  Save complete project to: /home/ga/Documents/surgical_views/skull_study.inv3
  (Must include: bone mask, 3D surface, and all measurements)

Note: Use the InVesalius 3D surface export/screenshot function to capture
the 3D views, not a desktop screenshot. Navigate the 3D viewer to the
correct orientation before capturing each view.
PROTOCOL

chown ga:ga "/home/ga/Documents/imaging_protocol.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
echo "0" > /tmp/surgical_views_png_count_initial
date +%s > /tmp/task_start_timestamp

# Close any existing InVesalius instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with CT Cranium pre-loaded
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

sleep 2
take_screenshot /tmp/task_start.png

echo "Output directory: $OUTPUT_DIR"
echo "Imaging protocol: /home/ga/Documents/imaging_protocol.txt"
echo "Expected PNGs: anterior_view.png, lateral_view.png, superior_view.png"
echo "Expected project: $OUTPUT_DIR/skull_study.inv3"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
