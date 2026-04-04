#!/bin/bash
# Setup script for forensic_craniometric_protocol task

set -e
echo "=== Setting up forensic_craniometric_protocol task ==="

source /workspace/scripts/task_utils.sh

# Use Fox sample dataset (0437) — a different patient/specimen from ct_cranium
FOX_URL="https://github.com/invesalius/invesalius3/releases/download/v3.0/0437.zip"
FOX_SAMPLE_DIR="/opt/invesalius/sample_data/fox_dataset"
FOX_DICOM_DIR="$FOX_SAMPLE_DIR/0437"
SERIES_DIR="/home/ga/DICOM/fox_dataset"

OUTPUT_DIR="/home/ga/Documents/forensic_case"

# Download Fox dataset if not already present
mkdir -p "$FOX_SAMPLE_DIR"
if ! find -L "$FOX_DICOM_DIR" -type f -print -quit 2>/dev/null | grep -q .; then
    echo "Downloading Fox DICOM dataset for forensic task..."
    tmp_zip=$(mktemp /tmp/fox_XXXX.zip)
    if curl -L --fail --retry 3 --connect-timeout 20 --max-time 300 \
        -o "$tmp_zip" "$FOX_URL"; then
        unzip -q -o "$tmp_zip" -d "$FOX_SAMPLE_DIR"
    elif wget --timeout=300 -O "$tmp_zip" "$FOX_URL"; then
        unzip -q -o "$tmp_zip" -d "$FOX_SAMPLE_DIR"
    else
        echo "Failed to download Fox dataset; falling back to ct_cranium." >&2
        FOX_SAMPLE_DIR="/opt/invesalius/sample_data/ct_cranium"
        FOX_DICOM_DIR="$FOX_SAMPLE_DIR"
        SERIES_DIR="/home/ga/DICOM/ct_cranium"
    fi
    rm -f "$tmp_zip"
fi

chown -R ga:ga "$FOX_SAMPLE_DIR" 2>/dev/null || true

# Symlink for ga user (idempotent)
mkdir -p /home/ga/DICOM
ln -sfn "$FOX_SAMPLE_DIR" "$SERIES_DIR" 2>/dev/null || true
chown -h ga:ga "$SERIES_DIR" 2>/dev/null || true

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove any pre-existing output files
rm -f "$OUTPUT_DIR/skull_surface.stl" \
      "$OUTPUT_DIR/forensic_analysis.inv3" \
      "$OUTPUT_DIR/norma_frontalis.png" \
      "$OUTPUT_DIR/norma_lateralis.png" \
      "$OUTPUT_DIR/norma_verticalis.png"

# Create forensic case brief document
cat > "$OUTPUT_DIR/case_brief.txt" << 'BRIEF'
FORENSIC ANTHROPOLOGY CASE BRIEF
=================================
Case Reference:  FA-2024-0117
Status:          Unidentified skeletal remains — CT imaging requested

Clinical Summary:
  Unidentified adult remains recovered. CT imaging performed for
  non-destructive craniometric analysis and forensic documentation.
  Biological profile estimation required for missing persons comparison.

DICOM Data:      CT series loaded in InVesalius
                 Axial CT slices, sub-millimeter in-plane resolution

Required Craniometric Protocol:
  A minimum of 10 linear measurements are required for FORDISC analysis.
  Standard measurements include:

  Cranial Vault Dimensions (mid-sagittal/bilateral):
    - Maximum Cranial Length (glabella to opisthocranion): anteroposterior
    - Maximum Cranial Breadth (biparietal): transverse
    - Cranial Height (basion to bregma): vertical

  Bilateral Measurements (measure BOTH left AND right sides):
    - Temporal lobe width (L and R)
    - Orbital width / height (L and R)
    - Mastoid process height (L and R)

  Additional optional measurements for completeness:
    - Forehead width (minimum frontal)
    - Bizygomatic width (if visible)

Required Deliverables:
  1. Bone segmentation mask (appropriate Hounsfield threshold for cortical bone)
  2. 3D bone surface mesh and STL export:
       /home/ga/Documents/forensic_case/skull_surface.stl
  3. Orientation screenshots of the 3D surface:
       - Norma frontalis (anterior view):
           /home/ga/Documents/forensic_case/norma_frontalis.png
       - Norma lateralis (lateral/side view):
           /home/ga/Documents/forensic_case/norma_lateralis.png
       - Norma verticalis (superior/top-down view):
           /home/ga/Documents/forensic_case/norma_verticalis.png
  4. Complete InVesalius project (bone mask + surface + all measurements):
       /home/ga/Documents/forensic_case/forensic_analysis.inv3

Case Priority: Standard (non-urgent)
BRIEF

chown ga:ga "$OUTPUT_DIR/case_brief.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
echo "false" > /tmp/forensic_stl_initial
echo "false" > /tmp/forensic_project_initial
date +%s > /tmp/task_start_timestamp

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
echo "Case brief: $OUTPUT_DIR/case_brief.txt"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
