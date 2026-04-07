#!/bin/bash
set -e
echo "=== Setting up probe_pixel_density task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure export directory exists
mkdir -p /home/ga/DICOM/exports
chown ga:ga /home/ga/DICOM/exports

# Remove any stale results
rm -f /home/ga/DICOM/exports/pixel_probe_results.txt

# Ensure synthetic DICOM files exist
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
DICOM_FILE="$SAMPLE_DIR/CT_slice_001.dcm"

if [ ! -f "$DICOM_FILE" ]; then
    echo "Synthetic DICOM not found, creating..."
    mkdir -p "$SAMPLE_DIR"
    python3 << 'PYEOF'
import os
import numpy as np
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian
import datetime

def create_sample_dicom(filename, slice_num=1, size=256):
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
    ds.PatientName = "Test^Patient"
    ds.PatientID = "TEST001"
    ds.PatientBirthDate = "19800101"
    ds.PatientSex = "O"
    ds.StudyDescription = "Sample CT Study"
    ds.SeriesDescription = "Sample CT Series"
    ds.InstanceNumber = slice_num
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
    
    # Create synthetic image data (gradient + high density circle in center)
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

sample_dir = "/home/ga/DICOM/samples/synthetic"
os.makedirs(sample_dir, exist_ok=True)
for i in range(3):
    create_sample_dicom(os.path.join(sample_dir, f"CT_slice_{i+1:03d}.dcm"), slice_num=i+1)
print("Synthetic DICOM files created")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
fi

# Compute and store ground truth pixel values
echo "Computing ground truth pixel values..."
python3 << 'PYEOF'
import json
import pydicom

dcm_path = "/home/ga/DICOM/samples/synthetic/CT_slice_001.dcm"
ds = pydicom.dcmread(dcm_path)
pixels = ds.pixel_array
slope = float(ds.RescaleSlope) if hasattr(ds, 'RescaleSlope') else 1.0
intercept = float(ds.RescaleIntercept) if hasattr(ds, 'RescaleIntercept') else 0.0

coords = [(128, 128), (64, 64), (192, 192)]
ground_truth = {}
for (col, row) in coords:  # standard image X, Y is col, row in numpy
    raw_val = int(pixels[row, col])
    hu_val = raw_val * slope + intercept
    ground_truth[f"{col},{row}"] = {
        "raw": raw_val,
        "hu": hu_val,
        "x": col,
        "y": row
    }

gt_path = "/tmp/ground_truth_pixels.json"
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)
print(f"Ground truth saved to {gt_path}")
PYEOF

chmod 644 /tmp/ground_truth_pixels.json

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
pkill -f weasis 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || true

# Wait for Weasis to start
echo "Waiting for Weasis window..."
wait_for_weasis 90

# Try to dismiss first-run dialog
sleep 5
dismiss_first_run_dialog
sleep 2

# Maximize Weasis window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_weasis

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="