#!/bin/bash
echo "=== Setting up Ellipsoid Volume Estimation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Setup directories
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Clean up any previous task artifacts
rm -f "$EXPORT_DIR/volume_report.json" 2>/dev/null || true
rm -f "$EXPORT_DIR/volume_measurements.png" 2>/dev/null || true

# Generate a synthetic CT with a distinct measurable central structure
echo "Preparing DICOM sample with measurable mass..."
mkdir -p "$SAMPLE_DIR/synthetic"
DICOM_FILE="$SAMPLE_DIR/synthetic/volume_test.dcm"

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
        ds.PatientName = "Volume^Test"
        ds.PatientID = "VOL001"
        ds.StudyDescription = "Ellipsoid Volume Test"
        
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
        ds.PixelSpacing = [1.0, 1.0] # 1mm per pixel for easy math
        ds.SliceThickness = 1.0
        
        # Create image
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 500  # Background tissue
        
        # Create a central elliptical "mass"
        center_x, center_y = size // 2, size // 2
        radius_x, radius_y = 60, 40  # ~120mm x 80mm
        
        for i in range(size):
            for j in range(size):
                # Equation of ellipse
                if ((i - center_y)**2 / radius_y**2) + ((j - center_x)**2 / radius_x**2) <= 1:
                    image[i, j] = 2000  # Bright structure
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created synthetic DICOM with central mass: {filename}")

    create_sample_dicom("/home/ga/DICOM/samples/synthetic/volume_test.dcm")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF

chown -R ga:ga "$SAMPLE_DIR"

# Ensure Weasis isn't already running
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with our specific file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Maximize Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Dismiss first-run dialog
sleep 2
dismiss_first_run_dialog
sleep 2

# Take initial screenshot for baseline
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="