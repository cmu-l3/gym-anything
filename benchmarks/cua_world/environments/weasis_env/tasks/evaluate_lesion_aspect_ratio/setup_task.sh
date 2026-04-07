#!/bin/bash
echo "=== Setting up Evaluate Lesion Aspect Ratio task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
EXPORT_DIR="/home/ga/DICOM/exports"

# Create directories
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$SAMPLE_DIR" "$EXPORT_DIR"

# Clean previous exports
rm -f "$EXPORT_DIR"/aspect_ratio_report.txt 2>/dev/null || true
rm -f "$EXPORT_DIR"/aspect_ratio_view.* 2>/dev/null || true

DICOM_FILE="$SAMPLE_DIR/CT_slice_001.dcm"

echo "Creating synthetic DICOM file with deliberately washed-out defaults..."
python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    size = 256
    filename = "/home/ga/DICOM/samples/synthetic/CT_slice_001.dcm"

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
    ds.Modality = "CT"
    ds.PatientName = "Lesion^Aspect^Ratio"
    ds.PatientID = "LAR001"
    ds.StudyDescription = "Aspect Ratio Evaluation"

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
    
    # Deliberately bad default Window/Level to force user adjustment
    # Image data range is 0 to ~4000. These settings will wash it out to pure white.
    ds.WindowCenter = 40
    ds.WindowWidth = 400

    image = np.zeros((size, size), dtype=np.uint16)
    
    # Background gradient 0 to 4000
    for i in range(size):
        for j in range(size):
            image[i, j] = int((i + j) * 4000 / (2 * size))
            
    # Add central circular structure (radius 64 -> diameter 128)
    center = size // 2
    radius = 64
    for i in range(size):
        for j in range(size):
            if (i - center)**2 + (j - center)**2 < radius**2:
                image[i, j] = 2000

    ds.PixelData = image.tobytes()
    ds.save_as(filename)
    print(f"Created: {filename}")
except Exception as e:
    print(f"Error: {e}")
PYEOF

chown ga:ga "$DICOM_FILE"

# Make sure Weasis is not running (fresh start)
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Maximize and focus
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog
sleep 2

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="