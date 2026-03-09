#!/bin/bash
set -e

echo "=== Setting up export_bone_vtp task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean environment
# Remove output file if it exists to prevent false positives
rm -f "/home/ga/Documents/cranial_bone.vtp"
# Ensure directory exists
mkdir -p "/home/ga/Documents"
chown ga:ga "/home/ga/Documents"

# 2. Record start state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_vtp_count

# 3. Verify DICOM data
SERIES_DIR="/home/ga/DICOM/ct_cranium"
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "ERROR: Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 4. Prepare Application
# Kill any existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# Allow automation on display
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# Launch InVesalius with data pre-loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius did not open within timeout." >&2
    tail -n 20 /tmp/invesalius_ga.log 2>/dev/null || true
    exit 1
fi
sleep 5

# 5. Window Management
dismiss_startup_dialogs
focus_invesalius || true

WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 6. Capture Evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Expected Output: /home/ga/Documents/cranial_bone.vtp"