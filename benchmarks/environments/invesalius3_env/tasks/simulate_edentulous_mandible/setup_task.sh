#!/bin/bash
set -e
echo "=== Setting up simulate_edentulous_mandible task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
STL_FILE="$OUTPUT_DIR/edentulous_skull.stl"
PNG_FILE="$OUTPUT_DIR/edentulous_view.png"

# cleanup previous run
rm -f "$STL_FILE"
rm -f "$PNG_FILE"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Ensure Data
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Clean Start
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Launch InVesalius
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for App
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 5

dismiss_startup_dialogs
focus_invesalius || true

# Maximize
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Initial Evidence
take_screenshot /tmp/task_initial.png

echo "Setup complete. Target output: $STL_FILE"