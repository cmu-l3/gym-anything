#!/bin/bash
echo "=== Setting up extract_dicom_uids_troubleshooting task ==="

# Try to source environment utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
    dismiss_first_run_dialog() { sleep 1; }
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create export directory with proper permissions
mkdir -p /home/ga/DICOM/exports
chown -R ga:ga /home/ga/DICOM/exports

# Clean up any files from previous runs
rm -f /home/ga/DICOM/exports/routing_info.txt
rm -f /home/ga/DICOM/exports/dicom_info_screen.png

# Find a DICOM file to load
DICOM_FILE=$(find /home/ga/DICOM/samples -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Save choice for the export script to compute ground truth
echo "$DICOM_FILE" > /tmp/task_dicom_file.txt

# Stop any existing Weasis processes
pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
if [ -n "$DICOM_FILE" ]; then
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
else
    echo "Warning: No DICOM files found in samples folder!"
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
fi

# Wait for Weasis window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "weasis"; then
        break
    fi
    sleep 2
done

# Allow time for data loading and dismiss dialogs
sleep 8
dismiss_first_run_dialog 2>/dev/null || true

# Maximize and focus Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="