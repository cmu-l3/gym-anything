#!/bin/bash
# Setup script for implant_sizing_measurements task

set -e
echo "=== Setting up implant_sizing_measurements task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_STL="$OUTPUT_DIR/implant_sizing.stl"
OUTPUT_PROJECT="$OUTPUT_DIR/implant_plan.inv3"

# Ensure output directory exists (owned by ga)
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files to prevent false positives
rm -f "$OUTPUT_STL" "$OUTPUT_PROJECT"

# Create a patient brief document to differentiate this task's starting state
cat > "$OUTPUT_DIR/patient_brief.txt" << 'BRIEF'
PATIENT INTAKE — CRANIAL IMPLANT SIZING REQUEST
================================================
Case Type: Cranioplasty (cranial vault reconstruction)
DICOM Data: CT Cranium series (ct_cranium/0051)
Acquisition: 108 axial slices, 0.957x0.957mm in-plane, 1.5mm slice thickness

Required Measurements for Implant Sizing:
  1. Maximum transverse diameter (widest left-right span of skull)
  2. Maximum anteroposterior diameter (longest front-to-back span)
  3. Skull height (vertex to foramen magnum base)
  4. At least 2 additional dimensions (e.g., temporal width, orbital width, parietal span)

Minimum 5 measurements required for the implant fabrication order.
Measurements must be placed on the CT slice views (axial/coronal/sagittal).

Export Requirements:
  - Bone surface: /home/ga/Documents/implant_sizing.stl (binary STL)
  - Project file: /home/ga/Documents/implant_plan.inv3
BRIEF

chown ga:ga "$OUTPUT_DIR/patient_brief.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
echo "false" > /tmp/implant_stl_exists_initial
echo "false" > /tmp/implant_project_exists_initial
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
echo "Patient brief: $OUTPUT_DIR/patient_brief.txt"
echo "Expected STL: $OUTPUT_STL"
echo "Expected project: $OUTPUT_PROJECT"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
