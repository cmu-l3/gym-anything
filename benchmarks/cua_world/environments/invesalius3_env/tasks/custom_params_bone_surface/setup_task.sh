#!/bin/bash
set -e
echo "=== Setting up custom_params_bone_surface task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_DIR="/home/ga/Documents"
PROJECT_FILE="$OUTPUT_DIR/cortical_project.inv3"
STL_FILE="$OUTPUT_DIR/cortical_bone.stl"

# 1. Clean previous artifacts
echo "Cleaning up output directory..."
mkdir -p "$OUTPUT_DIR"
rm -f "$PROJECT_FILE" "$STL_FILE"
chown ga:ga "$OUTPUT_DIR"

# 2. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Data is present
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 4. Prepare Application State
# Kill existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow X automation
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with data loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 120; then
    echo "InVesalius failed to launch." >&2
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

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="