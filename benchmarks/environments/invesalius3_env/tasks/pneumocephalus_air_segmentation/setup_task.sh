#!/bin/bash
# Setup script for pneumocephalus_air_segmentation task

set -e
echo "=== Setting up pneumocephalus_air_segmentation task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents/air_analysis"
OUTPUT_STL="$OUTPUT_DIR/air_spaces.stl"
OUTPUT_PROJECT="$OUTPUT_DIR/pneumocephalus_study.inv3"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files to prevent false positives
rm -f "$OUTPUT_STL" "$OUTPUT_PROJECT"

# Create a radiology request form that differentiates this task's starting state
cat > "$OUTPUT_DIR/radiology_request.txt" << 'REQEOF'
RADIOLOGY CONSULTATION REQUEST — TRAUMA UNIT
=============================================
Request Type:    CT Cranium — Pneumocephalus Assessment
Clinical Info:   Patient sustained head trauma. Evaluate for intracranial air
                 (pneumocephalus) and document paranasal sinus air space integrity.

DICOM Data:      CT Cranium series (ct_cranium/0051)
                 108 axial slices, 0.957x0.957 mm in-plane, 1.5 mm slice thickness

Radiologist Tasks:
  1. Segment and visualise intracranial and paranasal sinus air spaces.
     Air appears as very dark (negative HU) regions on CT.
     Use a Hounsfield threshold MAXIMUM of -200 HU or below to isolate air.

  2. Segment brain soft tissue separately for comparison.
     Brain parenchyma: approximately -100 to +80 HU.

  3. Measure the dimensions of major air-filled cavities (frontal sinus,
     ethmoid air cells, sphenoid sinus) using the linear measurement tool.
     At least 4 measurements required.

  4. Export the 3D air space surface model as STL:
       /home/ga/Documents/air_analysis/air_spaces.stl

  5. Save complete InVesalius project (both masks + all measurements):
       /home/ga/Documents/air_analysis/pneumocephalus_study.inv3

Clinical Note: Air (pneumocephalus) on CT appears BLACK — Hounsfield values
               are approximately -1000 HU. Sinuses normally filled with air
               are also black. These are the target structures.
REQEOF

chown ga:ga "$OUTPUT_DIR/radiology_request.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
echo "false" > /tmp/pneumo_stl_exists_initial
echo "false" > /tmp/pneumo_project_exists_initial
date +%s > /tmp/task_start_timestamp

# Close any existing InVesalius instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with CT Cranium pre-loaded
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window to appear
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
echo "Radiology request: $OUTPUT_DIR/radiology_request.txt"
echo "Expected STL: $OUTPUT_STL"
echo "Expected project: $OUTPUT_PROJECT"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
