#!/bin/bash
echo "=== Setting up apply_color_lut task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Prepare export directory and remove any existing artifact
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
rm -f "$EXPORT_DIR/colorized_ct.png"

# Find a real DICOM file to load (prefer real downloaded samples over synthetic)
DICOM_FILE=$(find /home/ga/DICOM/samples -type f \( -iname "*.dcm" \) ! -path "*/synthetic/*" 2>/dev/null | head -1)

# Fallback to any DICOM if real ones aren't found
if [ -z "$DICOM_FILE" ]; then
    DICOM_FILE=$(find /home/ga/DICOM/samples -type f -iname "*.dcm" 2>/dev/null | head -1)
fi

echo "Using DICOM file: $DICOM_FILE"

# Ensure Weasis is not already running
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Starting Weasis..."
if [ -n "$DICOM_FILE" ]; then
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
fi

# Wait for Weasis window to appear
wait_for_weasis 60
sleep 5

# Maximize and focus the window
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis 2>/dev/null || true
fi

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Ensure window is maximized again just in case dialog interfered
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="