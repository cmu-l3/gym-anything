#!/bin/bash
set -e
echo "=== Setting up report_mesh_statistics task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
STL_FILE="$OUTPUT_DIR/skull.stl"
REPORT_FILE="$OUTPUT_DIR/mesh_stats.txt"

# Ensure output directory exists and is owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Clean up any previous artifacts
rm -f "$STL_FILE"
rm -f "$REPORT_FILE"

# Ensure data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Reset InVesalius state
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
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
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

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Expected STL output: $STL_FILE"
echo "Expected Report output: $REPORT_FILE"
echo "=== Setup Complete ==="