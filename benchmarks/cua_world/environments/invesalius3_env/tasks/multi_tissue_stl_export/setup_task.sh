#!/bin/bash
set -e
echo "=== Setting up multi_tissue_stl_export task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
BONE_FILE="$OUTPUT_DIR/bone_model.stl"
SKIN_FILE="$OUTPUT_DIR/skin_model.stl"

# 1. Clean up previous artifacts
echo "Cleaning up previous output files..."
mkdir -p "$OUTPUT_DIR"
rm -f "$BONE_FILE" "$SKIN_FILE"
chown -R ga:ga "$OUTPUT_DIR"

# 2. Verify Data Availability
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 3. Prepare Application State
# Close any running instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation for user ga
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with data pre-loaded
echo "Launching InVesalius 3..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 4. Wait for Application Ready
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    take_screenshot /tmp/setup_fail.png
    exit 1
fi
sleep 5

# 5. UI Setup (Dismiss dialogs, Maximize)
dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 6. Record Initial State
# Record start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_timestamp

# Take evidence screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Expected Bone STL: $BONE_FILE"
echo "Expected Skin STL: $SKIN_FILE"