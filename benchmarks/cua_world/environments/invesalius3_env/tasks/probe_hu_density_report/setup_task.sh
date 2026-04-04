#!/bin/bash
set -e
echo "=== Setting up probe_hu_density_report task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_FILE="/home/ga/Documents/hu_density_report.txt"

# 1. Prepare Environment
# Ensure DICOM data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Clean up any previous run artifacts
rm -f "$OUTPUT_FILE"
mkdir -p "$(dirname "$OUTPUT_FILE")"
chown ga:ga "$(dirname "$OUTPUT_FILE")"

# Kill existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 2. Launch Application
# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with DICOM pre-loaded
echo "Launching InVesalius with data from $IMPORT_DIR..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 3. Wait for Application Ready
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    take_screenshot /tmp/setup_fail.png
    exit 1
fi
sleep 3

# Dismiss dialogs and maximize
dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 4. Record Initial State
# Record start time for anti-gaming (file must be created AFTER this)
date +%s > /tmp/task_start_time.txt

# Take evidence screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Output expected at: $OUTPUT_FILE"