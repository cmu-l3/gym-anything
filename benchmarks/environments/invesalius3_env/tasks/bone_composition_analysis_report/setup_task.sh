#!/bin/bash
set -e
echo "=== Setting up bone_composition_analysis_report task ==="

source /workspace/scripts/task_utils.sh

# Paths
SERIES_DIR="/home/ga/DICOM/ct_cranium"
DOCS_DIR="/home/ga/Documents"
PROJECT_FILE="$DOCS_DIR/bone_analysis.inv3"
REPORT_FILE="$DOCS_DIR/bone_report.txt"

# Clean up previous artifacts
rm -f "$PROJECT_FILE" "$REPORT_FILE"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure DICOM data exists
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Kill existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Grant X permissions
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with data loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="