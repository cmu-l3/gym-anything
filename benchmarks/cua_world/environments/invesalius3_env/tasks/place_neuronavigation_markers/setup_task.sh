#!/bin/bash
set -e
echo "=== Setting up place_neuronavigation_markers task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
DOCS_DIR="/home/ga/Documents"
REPORT_FILE="$DOCS_DIR/fiducial_report.txt"
PROJECT_FILE="$DOCS_DIR/neuronavigation_plan.inv3"

# 1. Clean up previous artifacts
rm -f "$REPORT_FILE"
rm -f "$PROJECT_FILE"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Ensure data exists
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 3. Clean start for InVesalius
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 4. Launch InVesalius with data pre-loaded
echo "Launching InVesalius..."
# Allow X access for ga
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
# Launch
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 5. Wait for application window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 50 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 5

# 6. Normalize window state (Focus & Maximize)
dismiss_startup_dialogs
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 7. Record verification baselines
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_report_exists.txt

# 8. Capture initial evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Report expected at: $REPORT_FILE"
echo "Project expected at: $PROJECT_FILE"