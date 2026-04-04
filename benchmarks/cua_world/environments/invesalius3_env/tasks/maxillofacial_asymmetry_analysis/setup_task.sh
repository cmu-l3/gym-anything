#!/bin/bash
# Setup script for maxillofacial_asymmetry_analysis task

set -e
echo "=== Setting up maxillofacial_asymmetry_analysis task ==="

source /workspace/scripts/task_utils.sh

# Use Fox sample dataset (0437) — a different patient/specimen from ct_cranium
FOX_URL="https://github.com/invesalius/invesalius3/releases/download/v3.0/0437.zip"
FOX_SAMPLE_DIR="/opt/invesalius/sample_data/fox_dataset"
FOX_DICOM_DIR="$FOX_SAMPLE_DIR/0437"
SERIES_DIR="/home/ga/DICOM/fox_dataset"

OUTPUT_DIR="/home/ga/Documents/asymmetry_study"

# Download Fox dataset if not already present
mkdir -p "$FOX_SAMPLE_DIR"
if ! find -L "$FOX_DICOM_DIR" -type f -print -quit 2>/dev/null | grep -q .; then
    echo "Downloading Fox DICOM dataset for maxillofacial task..."
    tmp_zip=$(mktemp /tmp/fox_XXXX.zip)
    if curl -L --fail --retry 3 --connect-timeout 20 --max-time 300 \
        -o "$tmp_zip" "$FOX_URL"; then
        unzip -q -o "$tmp_zip" -d "$FOX_SAMPLE_DIR"
    elif wget --timeout=300 -O "$tmp_zip" "$FOX_URL"; then
        unzip -q -o "$tmp_zip" -d "$FOX_SAMPLE_DIR"
    else
        echo "Failed to download Fox dataset; falling back to ct_cranium." >&2
        SERIES_DIR="/home/ga/DICOM/ct_cranium"
    fi
    rm -f "$tmp_zip"
fi

chown -R ga:ga "$FOX_SAMPLE_DIR" 2>/dev/null || true
mkdir -p /home/ga/DICOM
ln -sfn "$FOX_SAMPLE_DIR" "$SERIES_DIR" 2>/dev/null || true
chown -h ga:ga "$SERIES_DIR" 2>/dev/null || true

mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Remove pre-existing output files
rm -f "$OUTPUT_DIR/skull_model.stl" \
      "$OUTPUT_DIR/asymmetry_analysis.inv3" \
      "$OUTPUT_DIR/anterior_view.png" \
      "$OUTPUT_DIR/left_lateral.png" \
      "$OUTPUT_DIR/right_lateral.png" \
      "$OUTPUT_DIR/superior_view.png" \
      "$OUTPUT_DIR/posterior_view.png"

# Create surgical assessment form
cat > "$OUTPUT_DIR/assessment_form.txt" << 'FORM'
ORAL & MAXILLOFACIAL SURGERY — ASYMMETRY ASSESSMENT FORM
==========================================================
Patient Reference:    MFS-2024-0089 (orthognathic surgery evaluation)
Chief Complaint:      Facial asymmetry, Class III malocclusion
DICOM Imaging:        CT cranial/maxillofacial series loaded in InVesalius

CLINICAL CONTEXT
-----------------
Patient presents with suspected hemimandibular hypertrophy (one side of the
lower jaw larger than the other). Pre-surgical CT documentation of craniofacial
asymmetry is required before orthognathic correction planning can begin.

REQUIRED BILATERAL MEASUREMENT PROTOCOL
-----------------------------------------
Minimum 12 measurements required. The protocol is BILATERAL:
you must measure corresponding structures on BOTH the left (L) AND right (R) sides.

Bilateral pairs (measure L and R at each anatomical location):
  Pair 1:  Temporal lobe width        — Left AND Right temporal regions
  Pair 2:  Orbital aperture width     — Left AND Right orbits
  Pair 3:  Mastoid process height     — Left AND Right mastoid processes
  Pair 4:  Parietal/zygomatic span    — Left AND Right lateral cranial surface

Overall/midline cranial measurements (at least 4):
  M1: Maximum cranial length (antero-posterior diameter, glabella to opisthocranion)
  M2: Maximum cranial breadth (biparietal transverse diameter)
  M3: Cranial height (basion to bregma)
  M4: Minimum frontal breadth (smallest transverse width of the frontal bone)

That gives a minimum of 8 bilateral + 4 midline = 12 total measurements.

REQUIRED 3D SURFACE DOCUMENTATION
------------------------------------
From the 3D bone surface reconstruction, capture and save screenshots
from FIVE standard anatomical orientations:

  1. Anterior view (norma frontalis — looking from the front)
       → /home/ga/Documents/asymmetry_study/anterior_view.png
  2. Left lateral view (looking from the patient's left side)
       → /home/ga/Documents/asymmetry_study/left_lateral.png
  3. Right lateral view (looking from the patient's right side)
       → /home/ga/Documents/asymmetry_study/right_lateral.png
  4. Superior view (norma verticalis — looking down from above)
       → /home/ga/Documents/asymmetry_study/superior_view.png
  5. Posterior view (norma occipitalis — looking from the back)
       → /home/ga/Documents/asymmetry_study/posterior_view.png

REQUIRED OUTPUT FILES
----------------------
  STL surface model: /home/ga/Documents/asymmetry_study/skull_model.stl
  InVesalius project: /home/ga/Documents/asymmetry_study/asymmetry_analysis.inv3
    (project must contain: bone mask + 3D surface + all 12+ measurements)

NOTES FOR MEASUREMENT PLACEMENT
---------------------------------
- Use the LINEAR MEASUREMENT TOOL in the CT slice views (axial/coronal/sagittal)
- For bilateral measurements: navigate to one side, measure, then navigate to
  the symmetric location on the opposite side and measure again
- Measurements below 10 mm will not be accepted (likely measurement errors)
- All measurements are saved automatically in the InVesalius project file
FORM

chown ga:ga "$OUTPUT_DIR/assessment_form.txt" 2>/dev/null || true

if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Record baseline state
date +%s > /tmp/task_start_timestamp
echo "false" > /tmp/asymmetry_stl_initial
echo "false" > /tmp/asymmetry_project_initial

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
echo "Assessment form: $OUTPUT_DIR/assessment_form.txt"
echo "DICOM import dir: $IMPORT_DIR"
echo "=== Setup Complete ==="
