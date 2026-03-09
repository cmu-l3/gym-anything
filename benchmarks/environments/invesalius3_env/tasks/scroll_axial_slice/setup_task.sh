#!/bin/bash
set -e

echo "=== Setting up scroll_axial_slice task ==="

source /workspace/scripts/task_utils.sh

SERIES_DIR="/home/ga/DICOM/ct_cranium"
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Close any existing InVesalius instances for a clean start
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow root-driven xdotool/wmctrl automation against the user's X session.
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with the DICOM series pre-loaded
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window and settle
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    DISPLAY=:1 wmctrl -l || true
    echo "=== /tmp/invesalius_ga.log (tail) ==="
    tail -n 120 /tmp/invesalius_ga.log 2>/dev/null || true
    take_screenshot /tmp/task_start.png
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Capture start state
take_screenshot /tmp/task_start.png

echo "DICOM series path: $SERIES_DIR"
echo "DICOM import dir: $IMPORT_DIR"
printenv | grep -E "DISPLAY" || true

echo "=== Task setup complete ==="
