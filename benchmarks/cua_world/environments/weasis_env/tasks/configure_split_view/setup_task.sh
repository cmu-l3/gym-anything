#!/bin/bash
echo "=== Setting up configure_split_view task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Create the expected output directory with proper permissions
mkdir -p /home/ga/DICOM/exports
chown -R ga:ga /home/ga/DICOM/exports
chmod 777 /home/ga/DICOM/exports

# Remove any previous artifacts
rm -f /home/ga/DICOM/exports/split_view.png 2>/dev/null || true

# Kill any existing Weasis instances
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the samples directory so multiple images are available to load
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '/home/ga/DICOM/samples' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '/home/ga/DICOM/samples' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis UI to fully appear
wait_for_weasis 60
sleep 5

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize and focus the Weasis window for the agent
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_weasis 2>/dev/null || true
sleep 2

# Take initial screenshot to capture the default 1x1 state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Weasis is running with DICOM samples."
echo "Agent must configure a 1x2 layout and save a screenshot to ~/DICOM/exports/split_view.png"