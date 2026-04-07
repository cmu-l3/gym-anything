#!/bin/bash
echo "=== Setting up inverted_anatomy_presentation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and are clean
mkdir -p /home/ga/DICOM/exports
rm -f /home/ga/DICOM/exports/lecture_slide.jpg 2>/dev/null || true
rm -f /home/ga/DICOM/exports/measurement.txt 2>/dev/null || true
chown -R ga:ga /home/ga/DICOM/exports
chmod 777 /home/ga/DICOM/exports

# Ensure sample DICOMs are populated
if [ -z "$(ls -A /home/ga/DICOM/samples/ 2>/dev/null)" ]; then
    /workspace/scripts/setup_weasis.sh
fi

# Start Weasis if not running
if ! is_weasis_running; then
    echo "Starting Weasis..."
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
    
    # Wait for Weasis
    wait_for_weasis 60
fi

# Dismiss any first run dialogs
sleep 2
dismiss_first_run_dialog

# Maximize and focus
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="