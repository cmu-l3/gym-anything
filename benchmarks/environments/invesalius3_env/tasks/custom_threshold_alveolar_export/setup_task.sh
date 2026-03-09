#!/bin/bash
set -e
echo "=== Setting up custom_threshold_alveolar_export task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Paths
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
PROJECT_FILE="$OUTPUT_DIR/alveolar_study.inv3"
STL_FILE="$OUTPUT_DIR/alveolar_surface.stl"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
rm -f "$PROJECT_FILE" "$STL_FILE"

# 2. Check Data
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 3. Clean Start
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 4. Launch InVesalius
echo "Launching InVesalius with data..."
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 5. Wait for Window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 20 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 3

dismiss_startup_dialogs
focus_invesalius || true

# 6. Maximize
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 7. Record Initial State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="