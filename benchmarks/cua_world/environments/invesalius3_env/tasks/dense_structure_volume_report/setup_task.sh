#!/bin/bash
set -e
echo "=== Setting up dense_structure_volume_report task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
DOCS_DIR="/home/ga/Documents"

# Ensure data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Clean previous artifacts
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"
rm -f "$DOCS_DIR/dense_structures.stl"
rm -f "$DOCS_DIR/dense_volume_report.txt"
rm -f "$DOCS_DIR/dense_analysis.inv3"

# Kill existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X access
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with data loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius timeout." >&2
    exit 1
fi
sleep 5

# Handle dialogs and focus
dismiss_startup_dialogs
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# Initial evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="