#!/bin/bash
set -e
echo "=== Setting up dual_quality_surface_export task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/skull_best.stl"
rm -f "$OUTPUT_DIR/skull_lowres.stl"
chown ga:ga "$OUTPUT_DIR"

# Ensure DICOM data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Clean up any running instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with data pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for application window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 20 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 5

# Handle startup dialogs and window management
dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Output requirements:"
echo "1. $OUTPUT_DIR/skull_best.stl (High Quality)"
echo "2. $OUTPUT_DIR/skull_lowres.stl (Lower Quality)"