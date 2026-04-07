#!/bin/bash
echo "=== Setting up create_secondary_capture task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create export directory and remove any existing target file
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/finding_sc.dcm"
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Determine sample data to load (prefer mr_scan, fallback to whatever is in samples)
SAMPLE_PATH="/home/ga/DICOM/samples/mr_scan"
if [ ! -d "$SAMPLE_PATH" ] || [ -z "$(ls -A $SAMPLE_PATH 2>/dev/null)" ]; then
    SAMPLE_PATH=$(find "/home/ga/DICOM/samples" -type f \( -name "*.dcm" -o -name "*.DCM" \) | head -1)
fi

echo "Using sample data at: $SAMPLE_PATH"

# Make sure Weasis is not already running
pkill -f weasis >/dev/null 2>&1 || true
sleep 2

# Launch Weasis with the sample data
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SAMPLE_PATH' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SAMPLE_PATH' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to start
sleep 8
wait_for_weasis 60

# Maximize Weasis window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait for UI and image to settle
sleep 3
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Weasis is running with a medical image loaded."
echo "Agent must draw an arrow and export a Secondary Capture to $EXPORT_DIR/finding_sc.dcm"