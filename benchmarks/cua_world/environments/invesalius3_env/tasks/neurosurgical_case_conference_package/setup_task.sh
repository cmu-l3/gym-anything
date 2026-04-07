#!/bin/bash
# Setup script for neurosurgical_case_conference_package task

set -e
echo "=== Setting up neurosurgical_case_conference_package task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents/case_conference"

# Ensure output directory exists (owned by ga)
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files to prevent false positives
rm -f "$OUTPUT_DIR/cortical_bone.stl"
rm -f "$OUTPUT_DIR/soft_tissue.ply"
rm -f "$OUTPUT_DIR/anterior_view.png"
rm -f "$OUTPUT_DIR/lateral_view.png"
rm -f "$OUTPUT_DIR/cross_section.png"
rm -f "$OUTPUT_DIR/case_package.inv3"

# Create case specification document
cat > "$OUTPUT_DIR/case_specs.txt" << 'SPECS'
NEUROSURGICAL CASE CONFERENCE — PREPARATION SPECIFICATIONS
============================================================
Case Type:       Pre-operative planning for calvarial reconstruction
Conference:      Neurosurgical case conference
DICOM Data:      CT Cranium series (ct_cranium/0051)
                 108 axial slices, 0.957 x 0.957 mm in-plane, 1.5 mm slice thickness

TISSUE SEGMENTATION REQUIRED
-------------------------------
Create the following segmentation masks in InVesalius:

1. CORTICAL BONE (dense compact bone only)
   HU range: 662 to 1988

2. FULL BONE (all osseous tissue)
   HU range: 226 to 3071

3. SOFT TISSUE (skin and subcutaneous tissue envelope)
   HU range: -700 to 225

4. CANCELLOUS BONE (trabecular/spongy bone interior)
   Derived via boolean subtraction: Full Bone MINUS Cortical Bone
   This isolates the porous bone compartment between cortical tables.

3D RECONSTRUCTION
-------------------
Generate 3D surfaces for:
  a) Cortical Bone — apply mesh smoothing (>= 5 iterations) and decimate
     to fewer than 300,000 triangles for 3D-print compatibility.
  b) Soft Tissue — set this surface semi-transparent so the bone model
     is visible underneath for anatomical context.

MEASUREMENTS
--------------
Place the following measurements using the appropriate InVesalius tools:
  - Maximum anteroposterior diameter (front to back, linear)
  - Maximum biparietal width (left to right, linear)
  - One orbital dimension (e.g., orbital width or height, linear)
  - Cranial base angle (angular measurement using 3-point angle tool)

DOCUMENTATION AND EXPORT
---------------------------
Export all deliverables to /home/ga/Documents/case_conference/:
  - cortical_bone.stl    Optimized cortical bone surface (binary STL)
  - soft_tissue.ply      Soft tissue envelope surface (PLY format)
  - anterior_view.png    Front-facing 3D screenshot (Norma Frontalis)
  - lateral_view.png     Right lateral 3D screenshot (Norma Lateralis)
  - cross_section.png    Sagittal clipping plane view showing internal
                         bone structure in the 3D viewer

Save the complete InVesalius project (all masks, surfaces, and
measurements) to:
  - case_package.inv3
SPECS

chown ga:ga "$OUTPUT_DIR/case_specs.txt" 2>/dev/null || true

# Validate DICOM data
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline timestamp
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
echo "Case specs: $OUTPUT_DIR/case_specs.txt"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
