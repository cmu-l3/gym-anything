#!/bin/bash
echo "=== Setting up export_dicom_secondary_capture task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and are clean
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/surgical_plan.dcm" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Ensure DICOM samples exist
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) | grep -i "ct" | head -1)

# Fallback to any dicom if no CT found
if [ -z "$DICOM_FILE" ]; then
    DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) | head -1)
fi

# Stop any running instances of Weasis to ensure clean state
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the target DICOM file
echo "Launching Weasis with $DICOM_FILE..."
if [ -n "$DICOM_FILE" ]; then
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
else
    # Fallback to open without file if none exist (should not happen given env setup)
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
fi

# Wait for Weasis UI to appear
wait_for_weasis 60
sleep 5

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Ensure window is maximized for agent visibility
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Take screenshot of initial state
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="