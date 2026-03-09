#!/bin/bash
set -e
echo "=== Setting up evaluate_morphological_closing_impact task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
RAW_STL="$OUTPUT_DIR/raw_skull.stl"
CLOSED_STL="$OUTPUT_DIR/closed_skull.stl"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
rm -f "$RAW_STL" "$CLOSED_STL"

# Ensure DICOM data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Reset InVesalius
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Launch InVesalius with data pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for application window
if ! wait_for_invesalius 180; then
    echo "InVesalius timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 5

# Handle dialogs and maximize
dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "Setup complete. Expecting outputs:"
echo "  1. $RAW_STL"
echo "  2. $CLOSED_STL"