#!/bin/bash
echo "=== Setting up measure_orthopedic_cobb_angle task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"

# Create/clean export directory
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/cobb_angle_result.png" 2>/dev/null || true
rm -f "$EXPORT_DIR/measurement_type.txt" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Record task start time (for anti-gaming timestamps)
date +%s > /tmp/task_start_time.txt

# Create a sample DICOM file with suitable structures if none exists
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

if [ -z "$DICOM_FILE" ]; then
    echo "Creating synthetic DICOM file..."
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
        ds.PatientName = "Spine^Phantom"
        ds.PatientID = "COBB001"
        ds.StudyDescription = "Orthopedic Angle Test"

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

        # Create basic structures to measure (simulating two tilted vertebrae/endplates)
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 200 # Background

        # Upper structure (tilted ~20 degrees)
        for i in range(100, 200):
            for j in range(150, 350):
                # Apply rotation
                y = i - 150
                x = j - 250
                if abs(y * 0.94 - x * 0.34) < 30 and abs(y * 0.34 + x * 0.94) < 80:
                    image[i, j] = 2000

        # Lower structure (tilted ~-15 degrees)
        for i in range(300, 400):
            for j in range(150, 350):
                # Apply opposite rotation
                y = i - 350
                x = j - 250
                if abs(y * 0.96 + x * 0.26) < 30 and abs(-y * 0.26 + x * 0.96) < 80:
                    image[i, j] = 2000

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "spine_phantom.dcm"))

except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/spine_phantom.dcm"
fi

echo "Using DICOM file: $DICOM_FILE"

# Kill any existing Weasis process
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to start
sleep 8
wait_for_weasis 60

# Dismiss dialogs and maximize
sleep 2
dismiss_first_run_dialog
sleep 2

WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot showing clean state
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="