#!/bin/bash
echo "=== Setting up calculate_cardiothoracic_ratio task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"

# Prepare pristine export directory
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Clear any previous task artifacts to prevent false positives
rm -f "$EXPORT_DIR/ctr_report.txt" 2>/dev/null || true
rm -f "$EXPORT_DIR/ctr_measurements.png" 2>/dev/null || true

# Locate the clinical CT scan (provided by environment setup)
SAMPLE_DIR="/home/ga/DICOM/samples/ct_scan"

# Fallback to synthetic if the public download failed during env setup
if [ ! -d "$SAMPLE_DIR" ] || [ -z "$(ls -A $SAMPLE_DIR 2>/dev/null)" ]; then
    echo "Clinical CT not found, falling back to synthetic DICOM..."
    SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
fi

# Get the first DICOM file to launch Weasis with
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Ensure Weasis is starting fresh
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis directly with the loaded study to save agent time
echo "Launching Weasis with CT scan: $DICOM_FILE"
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis UI to appear
wait_for_weasis 60

# Dismiss standard first-run disclaimer
sleep 2
dismiss_first_run_dialog

# Maximize Weasis explicitly for the agent
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Allow image to fully render in viewpane
sleep 3

# Capture initial state proving application is running and loaded
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="