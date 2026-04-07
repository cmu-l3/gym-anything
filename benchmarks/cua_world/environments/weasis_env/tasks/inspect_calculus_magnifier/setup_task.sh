#!/bin/bash
echo "=== Setting up inspect_calculus_magnifier task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any existing export files to prevent gaming
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/lens_view.png" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Ensure we have a specific DICOM file with a bright central structure
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
mkdir -p "$SAMPLE_DIR"
DICOM_FILE="$SAMPLE_DIR/calculus_test.dcm"

echo "Creating targeted synthetic DICOM file..."
python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, size=512):
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
        ds.PatientName = "Calculus^Test"
        ds.PatientID = "CALC001"
        ds.StudyDescription = "Magnifier Tool Test"
        
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
        
        # Create image with a clear bright central structure (simulated calculus)
        image = np.zeros((size, size), dtype=np.uint16)
        
        # Background gradient
        for i in range(size):
            for j in range(size):
                image[i, j] = int((i + j) * 2000 / (2 * size))
                
        # Bright central circle
        center = size // 2
        radius = size // 12
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < radius:
                    image[i, j] = 3800  # High HU value, very bright
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    create_sample_dicom("/home/ga/DICOM/samples/synthetic/calculus_test.dcm")
except Exception as e:
    print(f"Error: {e}")
PYEOF
chown -R ga:ga "$SAMPLE_DIR"

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Maximize Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait a bit more for UI to settle
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="