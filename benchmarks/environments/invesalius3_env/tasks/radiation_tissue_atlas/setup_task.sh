#!/bin/bash
# Setup script for radiation_tissue_atlas task

set -e
echo "=== Setting up radiation_tissue_atlas task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents/rt_planning"

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove pre-existing outputs
rm -f "$OUTPUT_DIR/brain_tissue.stl" \
      "$OUTPUT_DIR/skull_bone.stl" \
      "$OUTPUT_DIR/periorbital_fat.stl" \
      "$OUTPUT_DIR/rt_tissue_atlas.inv3"

# Create treatment planning brief
cat > "$OUTPUT_DIR/planning_brief.txt" << 'BRIEF'
RADIATION TREATMENT PLANNING BRIEF
====================================
Patient:         Adult — Brain RT Planning (anonymised)
Modality:        CT Cranium (ct_cranium/0051)
                 108 axial slices, 0.957 × 0.957 mm in-plane, 1.5 mm slice thickness
Treatment:       Whole-brain or focal brain radiotherapy
Physicist Task:  CT tissue atlas generation for treatment planning system import

TISSUE DELINEATION REQUIREMENTS
--------------------------------
InVesalius must generate three separate segmentation masks:

1. BRAIN SOFT TISSUE (Primary Target Volume / GTV proxy)
   Hounsfield range: approximately -50 to +50 HU (brain parenchyma)
   CONSTRAINT: minimum HU must be >= -100; maximum HU must be <= 80
   Purpose: Defines the radiation target and brain tissue at risk.

2. COMPACT BONE / SKULL (Critical Structure)
   Hounsfield range: approximately 662 to 2000 HU (dense cortical bone)
   CONSTRAINT: minimum HU must be >= 600
   Purpose: Skull acts as dose-modifying structure — must be delineated
   for heterogeneity correction and surface dose calculation.

3. PERIORBITAL FAT (Organ at Risk — OAR)
   Hounsfield range: approximately -200 to -30 HU (orbital adipose tissue)
   CONSTRAINT: maximum HU must be <= -20; minimum HU must be >= -300
   Purpose: Orbital fat is adjacent to treatment fields — dose must be
   constrained to avoid radiation-induced retinopathy.

Each tissue requires:
  a) A segmentation mask with the specified HU range
  b) A 3D surface mesh generated from the mask
  c) STL export to the path listed below

REQUIRED OUTPUTS
----------------
  Brain tissue STL:   /home/ga/Documents/rt_planning/brain_tissue.stl
  Skull bone STL:     /home/ga/Documents/rt_planning/skull_bone.stl
  Periorbital fat STL:/home/ga/Documents/rt_planning/periorbital_fat.stl
  Project file:       /home/ga/Documents/rt_planning/rt_tissue_atlas.inv3
    (project must contain all 3 masks, 3 surfaces, and >= 5 measurements)

MEASUREMENTS REQUIRED
---------------------
Place at least 5 linear measurements in the slice views documenting:
  - Overall brain diameter (AP and/or transverse)
  - Skull-to-brain inner surface distance at vertex
  - Orbital height or width at periorbital fat location
  - Any additional inter-tissue distance relevant to field margin planning

Isocenter will be placed at geometric centre of brain tissue volume.
Field margins: Brain tissue + 10 mm (standard WBRT margin).
BRIEF

chown ga:ga "$OUTPUT_DIR/planning_brief.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
date +%s > /tmp/task_start_timestamp
echo "false" > /tmp/rt_project_initial

# Close existing InVesalius instances
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

sleep 2
take_screenshot /tmp/task_start.png

echo "Output directory: $OUTPUT_DIR"
echo "Planning brief: $OUTPUT_DIR/planning_brief.txt"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
