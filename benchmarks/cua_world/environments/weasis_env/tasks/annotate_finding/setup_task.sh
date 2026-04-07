#!/bin/bash
echo "=== Setting up annotate_finding task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is clean
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/annotated_finding.jpg" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Locate a REAL DICOM file (Preferring the ct_scan from rubomedical downloaded in environment setup)
DICOM_DIR="/home/ga/DICOM/samples/ct_scan"
DICOM_FILE=""

# Check if real CT scan exists
if [ -d "$DICOM_DIR" ]; then
    DICOM_FILE=$(find "$DICOM_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o -name "*[0-9]" \) 2>/dev/null | head -1)
fi

# Fallback to any DICOM file if the specific real CT scan isn't found
if [ -z "$DICOM_FILE" ]; then
    echo "Primary CT scan not found, looking for alternative DICOM samples..."
    DICOM_FILE=$(find /home/ga/DICOM/samples -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
fi

if [ -z "$DICOM_FILE" ]; then
    echo "ERROR: No DICOM files found to load. Environment setup may have failed."
    # We exit gracefully but this shouldn't happen if setup_weasis.sh ran
    exit 1
fi

echo "Using DICOM file: $DICOM_FILE"

# Kill any existing Weasis instances
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the real DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to load
wait_for_weasis 60
sleep 8

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize and focus the Weasis window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Export Target: $EXPORT_DIR/annotated_finding.jpg"
echo "Expected Text: 'Suspected lesion'"