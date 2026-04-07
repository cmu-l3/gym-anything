#!/bin/bash
set -e
echo "=== Setting up measure_angle_tool task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is clean
mkdir -p /home/ga/DICOM/exports
rm -f /home/ga/DICOM/exports/angle_measurement.png 2>/dev/null || true
rm -f /home/ga/DICOM/exports/angle_report.txt 2>/dev/null || true
chown -R ga:ga /home/ga/DICOM/exports

# Find a DICOM file to load (using shared util or fallback)
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Generate synthetic DICOM if no real samples found
if [ -z "$DICOM_FILE" ]; then
    echo "Creating synthetic DICOM file for angle measurement..."
    mkdir -p "$SAMPLE_DIR/synthetic"
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
        ds.PatientName = "Angle^Test"
        ds.PatientID = "ANG001"
        ds.StudyDescription = "Angle Measurement Test"
        
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

        # Draw a shape with clear angles (a wedge/triangle)
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 500  # background
        
        # Draw a dense triangle for measuring
        for i in range(size):
            for j in range(size):
                if i > 150 and i < 350 and j > 150:
                    if j < (i - 150) * 1.5 + 150:
                        image[i, j] = 2000

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "angle_test.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/angle_test.dcm"
fi

echo "Using DICOM file: $DICOM_FILE"

# Kill any existing Weasis instances
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis with DICOM file..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis window
wait_for_weasis 60

# Dismiss any first-run dialogs
sleep 3
dismiss_first_run_dialog
sleep 2

# Maximize Weasis window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus Weasis
focus_weasis
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "DICOM file loaded: $DICOM_FILE"
echo "Export directory ready: /home/ga/DICOM/exports/"