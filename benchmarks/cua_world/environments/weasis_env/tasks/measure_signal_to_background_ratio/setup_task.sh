#!/bin/bash
echo "=== Setting up measure_signal_to_background_ratio task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up and prepare the exports directory
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/bone_air_ratio.txt"
rm -f "$EXPORT_DIR/qa_rois.png"
chown -R ga:ga "$EXPORT_DIR"

# Ensure Weasis is running
ensure_weasis_running
sleep 2

# Maximize and focus Weasis window so the agent has a clear view
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Clear any popups that might obstruct the agent
dismiss_first_run_dialog
sleep 2

# Verify sample data exists
if [ ! -d "/home/ga/DICOM/samples/ct_scan" ] || [ -z "$(ls -A /home/ga/DICOM/samples/ct_scan 2>/dev/null)" ]; then
    echo "Notice: ct_scan folder empty or missing, agent will use synthetic fallback."
fi

# Capture the initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="