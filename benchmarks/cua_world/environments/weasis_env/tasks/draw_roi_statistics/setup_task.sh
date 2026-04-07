#!/bin/bash
echo "=== Setting up draw_roi_statistics task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback basic utilities
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
    wait_for_weasis() { sleep 10; }
    dismiss_first_run_dialog() { DISPLAY=:1 xdotool key Escape 2>/dev/null || true; }
fi

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
DICOM_FILE="$SAMPLE_DIR/CT_slice_roi.dcm"

# 1. Clean state: remove any prior task artifacts
echo "Cleaning up export directory..."
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/roi_statistics.txt 2>/dev/null || true
rm -f "$EXPORT_DIR"/roi_annotated.* 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# 2. Generate the synthetic CT image with a bright central circle
echo "Creating synthetic DICOM file..."
mkdir -p "$SAMPLE_DIR"
python3 << 'PYEOF'
import os
import numpy as np

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    filename = "/home/ga/DICOM/samples/synthetic/CT_slice_roi.dcm"
    size = 256
    
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2' # CT Image Storage
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
    ds.Modality = "CT"
    ds.PatientName = "ROI^Task"
    ds.PatientID = "ROI001"
    ds.StudyDescription = "ROI Statistics Task"
    
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
    ds.WindowCenter = 40
    ds.WindowWidth = 400

    # Image: gradient background with bright central circle
    image = np.zeros((size, size), dtype=np.uint16)
    for i in range(size):
        for j in range(size):
            image[i, j] = int((i + j) * 4000 / (2 * size))
            
    center = size // 2
    radius = size // 4
    for i in range(size):
        for j in range(size):
            if (i - center)**2 + (j - center)**2 < radius**2:
                image[i, j] = 2000

    ds.PixelData = image.tobytes()
    ds.save_as(filename)
    print(f"Created target DICOM: {filename}")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF
chown -R ga:ga "$SAMPLE_DIR"

# 3. Kill existing Weasis instance to start fresh
pkill -f weasis 2>/dev/null || true
sleep 2

# 4. Launch Weasis with our target DICOM
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to load
wait_for_weasis 60
sleep 5

# Dismiss first-run wizard if active
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Take initial screenshot for reference
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="