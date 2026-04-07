#!/bin/bash
echo "=== Setting up correct_orientation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
EXPECTED_EXPORT="$EXPORT_DIR/corrected_orientation.png"

# Ensure export directory exists and is clean of the target file
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
rm -f "$EXPECTED_EXPORT"

# Find a real DICOM file (preferring the CT/MR samples downloaded by the env)
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) | grep -i "ct_scan\|mr_scan" | head -1)

# Fallback if specific folders aren't found
if [ -z "$DICOM_FILE" ]; then
    DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
fi

if [ -z "$DICOM_FILE" ]; then
    echo "ERROR: No real DICOM files found in $SAMPLE_DIR. Environment setup failed to provide real data."
    # Absolute last resort fallback to prevent crash, though real data is required
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    filename = "/home/ga/DICOM/samples/synthetic/fallback.dcm"
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
    ds.ContentDate = datetime.datetime.now().strftime('%Y%m%d')
    ds.ContentTime = datetime.datetime.now().strftime('%H%M%S.%f')
    ds.StudyInstanceUID = generate_uid()
    ds.SeriesInstanceUID = generate_uid()
    ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
    ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
    ds.Modality = "CT"
    ds.PatientName = "Fallback^Test"
    ds.PatientID = "FB001"
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = 512
    ds.Columns = 512
    ds.BitsAllocated = 16
    ds.BitsStored = 12
    ds.HighBit = 11
    ds.PixelRepresentation = 0
    ds.RescaleIntercept = -1024
    ds.RescaleSlope = 1
    ds.WindowCenter = 40
    ds.WindowWidth = 400
    
    # Create an asymmetric pattern (like a large 'F') so rotation/flip is visible
    image = np.zeros((512, 512), dtype=np.uint16)
    image[100:400, 150:200] = 2000 # vertical stem
    image[100:150, 200:350] = 2000 # top horizontal
    image[220:270, 200:300] = 2000 # middle horizontal
    
    ds.PixelData = image.tobytes()
    ds.save_as(filename)
except Exception as e:
    print(f"Error creating fallback: {e}")
PYEOF
    DICOM_FILE="$SAMPLE_DIR/synthetic/fallback.dcm"
fi

echo "Using DICOM file: $DICOM_FILE"

# Make sure Weasis is not running from a previous task
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
if command -v /snap/bin/weasis &> /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
fi

# Wait for Weasis to load fully
wait_for_weasis 60
sleep 8

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi
sleep 2

# Take initial screenshot showing original orientation
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="