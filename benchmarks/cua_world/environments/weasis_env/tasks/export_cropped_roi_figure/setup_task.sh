#!/bin/bash
echo "=== Setting up export_cropped_roi_figure task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create export directory and clear old files
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/figure_roi.jpg" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Generate a custom synthetic DICOM with 4 distinct quadrants
# This allows the VLM to easily verify if the export is a sub-region (1 shape visible)
# instead of the full image (4 shapes visible).
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
mkdir -p "$SAMPLE_DIR"
DICOM_FILE="$SAMPLE_DIR/quadrant_test_highres.dcm"

echo "Creating synthetic high-res DICOM file..."
python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    size = 1024
    filename = "/home/ga/DICOM/samples/synthetic/quadrant_test_highres.dcm"

    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

    ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
    dt = datetime.datetime.now()
    ds.ContentDate = dt.strftime('%Y%m%d')
    ds.ContentTime = dt.strftime('%H%M%S.%f')
    ds.StudyInstanceUID = generate_uid()
    ds.SeriesInstanceUID = generate_uid()
    ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
    ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
    ds.Modality = "CR"
    ds.PatientName = "Quadrant^CropTest"
    ds.PatientID = "CROP001"
    ds.StudyDescription = "High-Res Sub-region Export Test"

    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = size
    ds.Columns = size
    ds.BitsAllocated = 16
    ds.BitsStored = 12
    ds.HighBit = 11
    ds.PixelRepresentation = 0
    ds.RescaleIntercept = -1024
    ds.RescaleSlope = 1
    ds.WindowCenter = 1000
    ds.WindowWidth = 2000

    # Base background
    image = np.zeros((size, size), dtype=np.uint16)
    image[:, :] = 200

    # Quadrant 1: Top-Left (Solid Circle)
    for i in range(512):
        for j in range(512):
            if (i-256)**2 + (j-256)**2 < 120**2:
                image[i, j] = 2000

    # Quadrant 2: Top-Right (Ring)
    for i in range(512):
        for j in range(512, 1024):
            dist = (i-256)**2 + (j-768)**2
            if 90**2 < dist < 140**2:
                image[i, j] = 2500

    # Quadrant 3: Bottom-Left (Square)
    for i in range(512, 1024):
        for j in range(512):
            if abs(i-768) < 110 and abs(j-256) < 110:
                image[i, j] = 1800

    # Quadrant 4: Bottom-Right (Cross)
    for i in range(512, 1024):
        for j in range(512, 1024):
            if (abs(i-768) < 130 and abs(j-768) < 30) or (abs(i-768) < 30 and abs(j-768) < 130):
                image[i, j] = 2200

    ds.PixelData = image.tobytes()
    ds.save_as(filename)
    print(f"Created high-res DICOM: {filename}")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF

chown -R ga:ga "$SAMPLE_DIR"

# Ensure Weasis is closed before starting
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the test file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application and dismiss dialogs
wait_for_weasis 60
sleep 4
dismiss_first_run_dialog
sleep 2

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="