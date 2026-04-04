#!/bin/bash
set -e
echo "=== Setting up visualize_cranial_cross_section task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_FILE="/home/ga/Documents/skull_cross_section.png"

# Ensure clean state
rm -f "$OUTPUT_FILE"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Ensure DICOM data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 2. Start Application
# Close any existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with DICOM pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    exit 1
fi
sleep 3

# 3. Configure Window
dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 4. Record Start State
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start.png

echo "Setup complete. Output expected at: $OUTPUT_FILE"