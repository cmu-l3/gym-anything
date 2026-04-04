#!/bin/bash
set -e
echo "=== Setting up simulate_thick_slab_xray task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Environment
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
CORONAL_FILE="$OUTPUT_DIR/coronal_thick_slab.png"
SAGITTAL_FILE="$OUTPUT_DIR/sagittal_thick_slab.png"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
rm -f "$CORONAL_FILE" "$SAGITTAL_FILE"
chown -R ga:ga "$OUTPUT_DIR"

# 2. Check Data
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 3. Clean Start InVesalius
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 4. Launch Application
# Allow root-driven automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
# Launch with data loaded
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_launch.log 2>&1 &"

# 5. Wait for Window and Maximize
if ! wait_for_invesalius 120; then
    echo "InVesalius failed to launch." >&2
    exit 1
fi
sleep 5

dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 6. Record Anti-Gaming Timestamp
date +%s > /tmp/task_start_time.txt

# 7. Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Coronal Output: $CORONAL_FILE"
echo "Target Sagittal Output: $SAGITTAL_FILE"