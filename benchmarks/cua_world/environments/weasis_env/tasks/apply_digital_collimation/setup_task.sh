#!/bin/bash
echo "=== Setting up apply_digital_collimation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create export directory and clear any existing artifacts
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
rm -f "$EXPORT_DIR/collimated_view.jpg"

# Ensure DICOM samples exist with a highly variable background
# This prevents the agent from passing without explicitly applying the shutter!
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
mkdir -p "$SAMPLE_DIR"
DICOM_FILE="$SAMPLE_DIR/collimation_target.dcm"

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
        ds.PatientName = "Collimation^Test"
        ds.PatientID = "COLLIM001"
        ds.StudyDescription = "Digital Shutter QA"

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

        # Create image with NOISY background (high variance) so shutter application is mathematically obvious
        image = np.random.normal(150, 40, (size, size)).astype(np.int16)
        
        # Add high-contrast central anatomy
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.35:
                    image[i, j] = 1200 + int(np.random.normal(50, 20))
                elif dist < size * 0.4:
                    image[i, j] = 800 + int(np.random.normal(30, 15))

        image = np.clip(image, 0, 4095).astype(np.uint16)
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    create_sample_dicom("/home/ga/DICOM/samples/synthetic/collimation_target.dcm")
except Exception as e:
    print(f"Error: {e}")
PYEOF

chown -R ga:ga "/home/ga/DICOM"

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the specific DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="