#!/bin/bash
set -e
echo "=== Setting up create_medical_illustration_base task ==="

source /workspace/scripts/task_utils.sh

# 1. Define paths
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/illustration_base.png"

# 2. Prepare environment
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true
# Remove existing output to ensure new creation
rm -f "$OUTPUT_FILE"

# 3. Ensure data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 4. Clean start
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 5. Launch InVesalius
# Use su - ga to run as user
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 6. Wait for application
if ! wait_for_invesalius 120; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    take_screenshot /tmp/setup_fail.png
    exit 1
fi
sleep 3

# 7. Configure Window
dismiss_startup_dialogs
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 8. Record State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "Expected output: $OUTPUT_FILE"
echo "=== Setup Complete ==="