#!/bin/bash
echo "=== Setting up Selective Measurement Deletion task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Export Directory & Clear Previous State
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"
rm -f "$EXPORT_DIR/selective_deletion.png" 2>/dev/null || true

# 2. Record Task Start Time for Anti-Gaming Verification
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_export_count

# 3. Secure Real DICOM Data (Not Synthetic)
SAMPLE_DIR="/home/ga/DICOM/samples/ct_scan"
mkdir -p "$SAMPLE_DIR"

DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

if [ -z "$DICOM_FILE" ]; then
    echo "Downloading real CT sample data from Rubo Medical..."
    wget -q "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip" -O /tmp/dicom_sample.zip
    if [ -f /tmp/dicom_sample.zip ]; then
        unzip -q -o /tmp/dicom_sample.zip -d "$SAMPLE_DIR/" 2>/dev/null || true
        rm -f /tmp/dicom_sample.zip
        DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
    fi
fi

if [ -z "$DICOM_FILE" ]; then
    echo "ERROR: Failed to download real DICOM data."
    exit 1
fi

chown -R ga:ga "/home/ga/DICOM"
echo "Using real DICOM file: $DICOM_FILE"

# 4. Ensure Clean State
pkill -f weasis 2>/dev/null || true
sleep 2

# 5. Launch Weasis Target Application
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for application window to appear
wait_for_weasis 60

# Maximize Window
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Allow UI to stabilize
sleep 2

# 6. Capture Initial State Screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Weasis is open with a real CT scan loaded."