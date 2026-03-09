#!/bin/bash
set -e
echo "=== Setting up raycasting_bone_visualization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define output path
OUTPUT_PATH="/home/ga/Documents/volume_render_bone.png"
DIR_PATH=$(dirname "$OUTPUT_PATH")

# Ensure output directory exists and has correct permissions
mkdir -p "$DIR_PATH"
chown ga:ga "$DIR_PATH"

# Remove previous output file to ensure fresh creation
rm -f "$OUTPUT_PATH"

# Define DICOM source
SERIES_DIR="/home/ga/DICOM/ct_cranium"

# Verify data exists
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Close any existing InVesalius instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow root-driven xdotool/wmctrl automation against the user's X session
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with the DICOM series pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window to appear
if ! wait_for_invesalius 120; then
    echo "InVesalius did not open within timeout." >&2
    exit 1
fi
sleep 5

# Handle startup dialogs
dismiss_startup_dialogs

# Maximize and focus
focus_invesalius || true
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="