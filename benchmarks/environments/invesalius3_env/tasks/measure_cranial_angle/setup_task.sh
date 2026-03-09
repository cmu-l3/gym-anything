#!/bin/bash
set -e
echo "=== Setting up measure_cranial_angle task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_FILE="$OUTPUT_DIR/cranial_angle.inv3"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true
rm -f "$OUTPUT_FILE"

# Ensure DICOM data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Close any existing InVesalius instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with DICOM pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window and settle
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    # Attempt fallback launch without -i if import fails
    echo "Retrying launch without auto-import..."
    pkill -f invesalius 2>/dev/null || true
    su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch > /tmp/invesalius_retry.log 2>&1 &"
    if ! wait_for_invesalius 120; then
        echo "InVesalius failed to launch."
        exit 1
    fi
fi
sleep 5

dismiss_startup_dialogs
focus_invesalius || true

# Maximize window
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Setup complete. Task start time recorded."