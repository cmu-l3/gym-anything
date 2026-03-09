#!/bin/bash
echo "=== Setting up open_dicom task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure DICOM samples exist
SAMPLE_DIR="/home/ga/DICOM/samples"
if [ ! -d "$SAMPLE_DIR" ] || [ -z "$(ls -A $SAMPLE_DIR 2>/dev/null)" ]; then
    echo "Creating sample DICOM files..."
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, modality="CT", size=256):
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
        ds.Modality = modality
        ds.PatientName = "Test^Patient"
        ds.PatientID = "TEST001"
        ds.PatientBirthDate = "19800101"
        ds.PatientSex = "O"
        ds.StudyDescription = f"Sample {modality} Study"
        ds.SeriesDescription = f"Sample {modality} Series"

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
        print(f"Created: {filename}")

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)

    for i in range(3):
        create_sample_dicom(
            os.path.join(sample_dir, f"CT_slice_{i+1:03d}.dcm"),
            modality="CT",
            size=256
        )
    print("Sample DICOM files created")

except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
fi

# Record initial state - no DICOM loaded yet
echo "0" > /tmp/initial_dicom_count

# Make sure Weasis is not running (fresh start)
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis to start
wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait a bit more for UI to settle
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "DICOM samples are in: $SAMPLE_DIR"
echo "Open any DICOM file from this directory in Weasis"
