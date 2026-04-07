#!/bin/bash
echo "=== Setting up DICOM Network Send Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing processes and states
echo "Cleaning up existing processes..."
pkill -f weasis 2>/dev/null || true
pkill -f storescp 2>/dev/null || true
sleep 2

# 2. Setup the hidden target directory for the PACS archive
TARGET_DIR="/home/ga/DICOM/pacs_archive"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
chown ga:ga "$TARGET_DIR"
chmod 777 "$TARGET_DIR"

# 3. Start the background DICOM receiver (storescp from dcmtk)
# -v enables verbose mode so we can grep the logs for Associations and C-STOREs
echo "Starting local PACS receiver on port 11112..."
rm -f /tmp/pacs_server.log
su - ga -c "dcmtk storescp -v -od '$TARGET_DIR' 11112 > /tmp/pacs_server.log 2>&1 &" || \
su - ga -c "storescp -v -od '$TARGET_DIR' 11112 > /tmp/pacs_server.log 2>&1 &"
sleep 2

# Verify receiver is running
if ! pgrep -f "storescp" > /dev/null; then
    echo "WARNING: storescp failed to start. Task verification may fail if dcmtk is missing."
else
    echo "Receiver is running and listening."
fi

# 4. Determine DICOM source directory (Prefer real data downloaded during env setup)
SAMPLE_DIR="/home/ga/DICOM/samples/ct_scan"
if [ ! -d "$SAMPLE_DIR" ] || [ -z "$(ls -A $SAMPLE_DIR 2>/dev/null)" ]; then
    echo "Real CT scan not found, falling back to synthetic samples..."
    SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
fi

# 5. Launch Weasis directly with the loaded series
echo "Launching Weasis with $SAMPLE_DIR..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to fully load the images
wait_for_weasis 60
sleep 8

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Focus and Maximize Weasis
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Weasis is running with loaded CT images."
echo "Local PACS receiver (storescp) is listening on port 11112."