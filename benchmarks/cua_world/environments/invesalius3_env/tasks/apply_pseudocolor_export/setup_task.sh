#!/bin/bash
set -e
echo "=== Setting up apply_pseudocolor_export task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_PATH="/home/ga/Documents/pseudocolor_view.png"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_PATH"
rm -f /tmp/task_result.json

# 2. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure InVesalius is running with data loaded
# Check if DICOM exists
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Restart InVesalius to ensure clean state (grayscale default)
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Grant X permissions
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius
echo "Launching InVesalius with dataset: $IMPORT_DIR"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 120; then
    echo "InVesalius launch failed or timed out."
    exit 1
fi
sleep 5

# Handle startup dialogs
dismiss_startup_dialogs
focus_invesalius || true

# Maximize window
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 4. Capture initial state (should be grayscale)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="