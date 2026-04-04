#!/bin/bash
set -e
echo "=== Setting up configure_mask_surface_properties task ==="

source /workspace/scripts/task_utils.sh

# Configuration
SERIES_DIR="/home/ga/DICOM/ct_cranium"
OUTPUT_FILE="/home/ga/Documents/organized_project.inv3"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"

# 2. Ensure DICOM data exists
if ! ensure_dicom_series_present "$SERIES_DIR"; then
    echo "Required DICOM series missing: $SERIES_DIR" >&2
    exit 1
fi
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# 3. Kill existing instances
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 4. Prepare environment
# Allow root-driven xdotool commands on user display
su - ga -c "DISPLAY=:1 xhost +local: >/dev/null 2>&1 || true"

# 5. Launch InVesalius with data loaded
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i \"$IMPORT_DIR\" > /tmp/invesalius_ga.log 2>&1 &"

# 6. Wait for application window
if ! wait_for_invesalius 120; then
    echo "InVesalius did not open within timeout." >&2
    exit 1
fi
sleep 3

# 7. Handle startup dialogs and window management
dismiss_startup_dialogs
focus_invesalius || true

# Maximize window
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 8. Record anti-gaming timestamps
date +%s > /tmp/task_start_time.txt

# 9. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="