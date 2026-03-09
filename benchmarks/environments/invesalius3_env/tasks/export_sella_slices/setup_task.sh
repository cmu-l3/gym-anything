#!/bin/bash
set -e

echo "=== Setting up export_sella_slices task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/axial_sella.png
rm -f /home/ga/Documents/sagittal_sella.png
rm -f /home/ga/Documents/coronal_sella.png
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Verify DICOM data is present
ensure_dicom_series_present "/home/ga/DICOM/ct_cranium" || {
    echo "ERROR: CT Cranium DICOM data not found"
    exit 1
}

IMPORT_DIR=$(pick_dicom_import_dir "/home/ga/DICOM/ct_cranium")
echo "DICOM import directory: $IMPORT_DIR"

# Clean up any existing instances
pkill -f invesalius 2>/dev/null || true
sleep 2

# Launch InVesalius with the DICOM data
echo "Starting InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch -i '$IMPORT_DIR' > /tmp/invesalius_launch.log 2>&1 &"

# Wait for InVesalius to appear
if ! wait_for_invesalius 120; then
    echo "ERROR: InVesalius failed to start"
    take_screenshot /tmp/setup_fail.png
    exit 1
fi

# Dismiss any startup dialogs (language selection, etc)
sleep 5
dismiss_startup_dialogs
sleep 2

# Maximize and focus
focus_invesalius
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Wait a bit for DICOM import to finalize (progress bar)
# A simple heuristic wait - import is usually fast for this dataset
sleep 10

# Final focus assurance
focus_invesalius
DISPLAY=:1 xdotool key Escape 2>/dev/null || true # Dismiss any lingering popups

# Take initial state screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="