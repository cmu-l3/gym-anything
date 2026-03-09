#!/bin/bash
set -e

echo "=== Setting up extract_dicom_parameters task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Environment
# ----------------------
# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of target file
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/ct_parameters.txt
chown ga:ga /home/ga/Documents

# 2. Extract Ground Truth from DICOM
# ----------------------------------
echo "Extracting ground truth from DICOM data..."
GROUND_TRUTH_DIR="/var/lib/invesalius_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"

# Locate the DICOM files
SERIES_DIR="/home/ga/DICOM/ct_cranium"
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "ERROR: Required DICOM series missing at $SERIES_DIR"
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")
SAMPLE_DCM=$(find -L "$IMPORT_DIR" -type f -print -quit 2>/dev/null)

# Default values
GT_SLICES="108"
GT_MATRIX_X="512"
GT_MATRIX_Y="512"
GT_SPACING="0.957"
GT_THICKNESS="1.5"
GT_MODALITY="CT"

# Use dcmdump if available to get exact values from the file on disk
if [ -n "$SAMPLE_DCM" ] && command -v dcmdump >/dev/null 2>&1; then
    # Slice count: count files in the directory
    GT_SLICES=$(find -L "$IMPORT_DIR" -type f | wc -l)
    
    # Matrix Rows (0028,0010)
    GT_MATRIX_X=$(dcmdump "$SAMPLE_DCM" 2>/dev/null | grep "(0028,0010)" | grep -oP '\[\K[0-9]+' | head -1 || echo "512")
    # Matrix Cols (0028,0011)
    GT_MATRIX_Y=$(dcmdump "$SAMPLE_DCM" 2>/dev/null | grep "(0028,0011)" | grep -oP '\[\K[0-9]+' | head -1 || echo "512")
    
    # Pixel Spacing (0028,0030) - usually "0.957\0.957", take first
    GT_SPACING=$(dcmdump "$SAMPLE_DCM" 2>/dev/null | grep "(0028,0030)" | grep -oP '\[\K[0-9.]+' | head -1 || echo "0.957")
    
    # Slice Thickness (0018,0050)
    GT_THICKNESS=$(dcmdump "$SAMPLE_DCM" 2>/dev/null | grep "(0018,0050)" | grep -oP '\[\K[0-9.]+' | head -1 || echo "1.5")
    
    # Modality (0008,0060)
    GT_MODALITY=$(dcmdump "$SAMPLE_DCM" 2>/dev/null | grep "(0008,0060)" | grep -oP '\[\K[A-Z0-9]+' | head -1 || echo "CT")
fi

# Save ground truth to hidden JSON
cat > "$GROUND_TRUTH_DIR/ground_truth.json" << EOF
{
    "slices": $GT_SLICES,
    "matrix_x": $GT_MATRIX_X,
    "matrix_y": $GT_MATRIX_Y,
    "pixel_spacing": $GT_SPACING,
    "slice_thickness": $GT_THICKNESS,
    "modality": "$GT_MODALITY"
}
EOF
chmod 644 "$GROUND_TRUTH_DIR/ground_truth.json"
echo "Ground truth saved."

# 3. Launch InVesalius
# --------------------
# Close any existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Launch with data loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i '$IMPORT_DIR' > /tmp/invesalius_launch.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 120; then
    echo "ERROR: InVesalius failed to launch."
    exit 1
fi
sleep 5

# Maximize and focus
dismiss_startup_dialogs
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 4. Final Prep
# -------------
# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="