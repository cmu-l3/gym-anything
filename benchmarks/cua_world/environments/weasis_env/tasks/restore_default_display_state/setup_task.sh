#!/bin/bash
echo "=== Setting up restore_default_display_state task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
SAMPLE_DIR="/home/ga/DICOM/samples"

# Ensure export directory exists and is empty to avoid stale files
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/state_*.jpg 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Find a real DICOM file from the environment's pre-downloaded samples
# Prioritize the real CT scan downloaded during env setup
DICOM_FILE=$(find "$SAMPLE_DIR/ct_scan" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Fallback to any DICOM file if the ct_scan folder is empty
if [ -z "$DICOM_FILE" ]; then
    DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
fi

if [ -z "$DICOM_FILE" ]; then
    echo "ERROR: No DICOM files found in $SAMPLE_DIR"
    exit 1
fi

echo "Using DICOM file: $DICOM_FILE"

# Make sure Weasis is not currently running
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis to be ready
wait_for_weasis 60

# Focus and maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait a bit more for UI to settle and DICOM to fully render
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="