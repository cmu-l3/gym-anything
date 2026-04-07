#!/bin/bash
echo "=== Setting up inspect_with_lens_tool task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Setup paths
EXPORT_DIR="/home/ga/DICOM/exports"
SAMPLE_DIR="/home/ga/DICOM/samples"

# Create export dir and clean previous attempts
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/lens_inspection.png" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Record start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Find a DICOM file (weasis_env prepares real samples in ~/DICOM/samples)
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Ensure Weasis is stopped before launching
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis with $DICOM_FILE..."
if [ -n "$DICOM_FILE" ]; then
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
else
    # Fallback to general launch if no file (agent will have to open one, though env guarantees samples)
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
fi

# Wait for Weasis UI to appear
wait_for_weasis 60
sleep 2

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    focus_window "$WID" 2>/dev/null || DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="