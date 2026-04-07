#!/bin/bash
echo "=== Setting up export_viewport_clipboard task ==="

source /workspace/scripts/task_utils.sh

EXPORT_DIR="/home/ga/DICOM/exports"
SAMPLE_DIR="/home/ga/DICOM/samples"

# 1. Clear any previous task artifacts
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
rm -f "$EXPORT_DIR/clipboard_dump.png"

# 2. Clear the X11 clipboard to ensure a clean slate
echo -n "" | DISPLAY=:1 xclip -selection clipboard 2>/dev/null || true

# 3. Ensure we have a REAL DICOM file (No synthetic data)
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

if [ -z "$DICOM_FILE" ]; then
    echo "Local DICOM not found. Downloading authentic medical sample..."
    mkdir -p "$SAMPLE_DIR/downloaded"
    # Download an authentic public domain CT sample from pydicom's official test suite
    wget -q "https://github.com/pydicom/pydicom/raw/main/pydicom/data/test_files/CT_small.dcm" -O "$SAMPLE_DIR/downloaded/CT_small.dcm"
    chown -R ga:ga "$SAMPLE_DIR/downloaded"
    DICOM_FILE="$SAMPLE_DIR/downloaded/CT_small.dcm"
    echo "Downloaded real CT sample to $DICOM_FILE"
fi

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Weasis
echo "Launching Weasis with $DICOM_FILE..."
pkill -f weasis 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to load
wait_for_weasis 60
sleep 4

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize Weasis for clear visibility
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Target DICOM: $DICOM_FILE"
echo "Export clipboard to: $EXPORT_DIR/clipboard_dump.png"