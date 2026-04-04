#!/bin/bash
# Setup script for cranioplasty_implant_pipeline task

set -e
echo "=== Setting up cranioplasty_implant_pipeline task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents/cranioplasty"

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove pre-existing output files
rm -f "$OUTPUT_DIR/cortical_bone.ply" \
      "$OUTPUT_DIR/cancellous_bone.stl" \
      "$OUTPUT_DIR/implant_fabrication.inv3"

# Create fabrication specification document
cat > "$OUTPUT_DIR/fab_specs.txt" << 'SPECS'
CRANIOPLASTY IMPLANT FABRICATION SPECIFICATION
================================================
Case Type:       Calvarial Reconstruction (Cranioplasty)
Material:        Patient-specific PEEK (polyetheretherketone) implant
Fabrication:     Additive manufacturing (FDM / SLS)
DICOM Data:      CT Cranium series (ct_cranium/0051)
                 108 axial slices, 0.957 × 0.957 mm in-plane, 1.5 mm slice thickness

BONE COMPARTMENT ANALYSIS REQUIRED
------------------------------------
Two bone compartments must be separately modelled:

1. CORTICAL BONE (Compact Bone — Outer Shell)
   Target HU range: 662 to 3071 HU (dense cortical/compact bone only)
   This is the load-bearing outer shell. The implant must match this geometry.
   Mesh preparation for 3D printing:
     a) Apply mesh smoothing: >= 10 iterations to reduce CT acquisition noise
     b) Apply decimation: target < 400,000 triangles (printer resolution limit)
   Export format: PLY (required by CAD software for implant design)
   Output path: /home/ga/Documents/cranioplasty/cortical_bone.ply

2. CANCELLOUS BONE (Trabecular / Spongy Bone — Interior)
   Target HU range: Full bone (226–3071 HU) MINUS compact bone (662–3071 HU)
   Use InVesalius boolean MINUS operation to isolate the cancellous compartment.
   This reveals the internal porous bone structure and guides implant porosity design.
   No mesh optimisation required for this surface.
   Export format: STL (for finite element analysis)
   Output path: /home/ga/Documents/cranioplasty/cancellous_bone.stl

WORKFLOW SUMMARY
-----------------
Step 1: Create full bone mask (Hounsfield 226–3071 HU)
Step 2: Create compact cortical bone mask (Hounsfield 662–3071 HU)
Step 3: Boolean subtraction: Full bone MINUS Compact bone → Cancellous bone mask
Step 4: Generate 3D surfaces for compact bone mask AND cancellous bone mask
Step 5: Optimise compact bone surface (smooth >= 10 iterations, then decimate to < 400,000 triangles)
Step 6: Export compact bone as PLY → /home/ga/Documents/cranioplasty/cortical_bone.ply
Step 7: Export cancellous bone as STL → /home/ga/Documents/cranioplasty/cancellous_bone.stl
Step 8: Place >= 5 calvarial measurements (skull thickness, span, vault dimensions)
Step 9: Save complete project → /home/ga/Documents/cranioplasty/implant_fabrication.inv3

DIMENSIONAL REQUIREMENTS
-------------------------
Implant sizing measurements needed:
  - Maximum calvarial transverse diameter (left to right)
  - Maximum calvarial anteroposterior diameter (front to back)
  - Skull thickness at vertex (cortical + cancellous + cortical)
  - At least 2 additional dimensions at implant site perimeter
Minimum 5 measurements required for implant sizing order.
SPECS

chown ga:ga "$OUTPUT_DIR/fab_specs.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
date +%s > /tmp/task_start_timestamp
echo "false" > /tmp/cranioplasty_ply_initial
echo "false" > /tmp/cranioplasty_stl_initial

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
echo "Fabrication specs: $OUTPUT_DIR/fab_specs.txt"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
