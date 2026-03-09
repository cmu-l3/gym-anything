#!/bin/bash
set -e
echo "=== Setting up export_model_with_patient_id task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"

# Ensure output directory exists and is empty of STLs to prevent false positives
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.stl
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Verify data availability
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Determine Ground Truth Patient ID for debugging/setup log
# (We use the first DICOM file found to extract the tag)
SAMPLE_DCM=$(find -L "$IMPORT_DIR" -type f \( -iname "*.dcm" -o -iname "*.dicom" -o -iname "*.ima" \) -print -quit)
if [ -n "$SAMPLE_DCM" ] && command -v dcmdump >/dev/null; then
    # Extract Patient ID (0010,0020), strip brackets [] and nulls
    GT_PATIENT_ID=$(dcmdump +P "0010,0020" "$SAMPLE_DCM" | sed -E 's/.*\[(.*)\].*/\1/' | tr -d '\0')
    echo "Ground Truth Patient ID: $GT_PATIENT_ID" > /tmp/ground_truth_id.txt
else
    echo "WARNING: Could not determine Patient ID during setup (dcmdump missing or no file)."
    echo "unknown" > /tmp/ground_truth_id.txt
fi

# Close any existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Launch InVesalius
echo "Launching InVesalius with data..."
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

# Maximize window
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Setup complete. Target ID recorded in /tmp/ground_truth_id.txt"