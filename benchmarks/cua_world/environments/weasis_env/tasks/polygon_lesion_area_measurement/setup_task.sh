#!/bin/bash
echo "=== Setting up polygon_lesion_area_measurement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up any previous attempts
rm -f "$EXPORT_DIR/polygon_area.png" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Generate a synthetic DICOM with a clearly irregular/lobulated lesion
DICOM_FILE="$SAMPLE_DIR/irregular_lesion.dcm"
echo "Creating DICOM with irregular lesion for polygon tracing..."

python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_lesion_dicom(filename, size=512):
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
        ds.PatientName = "Lesion^PolygonTest"
        ds.PatientID = "POLY001"
        ds.StudyDescription = "Irregular Lesion Measurement"

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
        ds.PixelSpacing = [1.0, 1.0]

        # Create image background
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 500
        
        # Add some anatomical context (a large soft tissue region)
        center = size // 2
        for i in range(size):
            for j in range(size):
                if (i - center)**2 + (j - center)**2 < (size*0.4)**2:
                    image[i, j] = 1000 + int(np.random.normal(0, 15))

        # Add a bright, irregular lobulated lesion in the center
        for i in range(size):
            for j in range(size):
                # Calculate polar coordinates from center
                dx = j - center
                dy = i - center
                theta = np.arctan2(dy, dx)
                
                # Create a star/lobulated shape radius
                # Base radius 40, plus 5 lobes of amplitude 15
                r = 40 + 15 * np.sin(5 * theta) + 5 * np.cos(3 * theta)
                
                if dx**2 + dy**2 < r**2:
                    # Lesion is bright
                    image[i, j] = 2000 + int(np.random.normal(0, 20))

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    create_lesion_dicom("/home/ga/DICOM/samples/synthetic/irregular_lesion.dcm")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF

chown -R ga:ga /home/ga/DICOM

# Stop any existing instances of Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the specific DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to load
wait_for_weasis 60
sleep 5

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize and focus Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true
sleep 1

# Take initial screenshot showing loaded state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="