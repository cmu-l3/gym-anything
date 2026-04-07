#!/bin/bash
echo "=== Setting up anonymize_dicom_export task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -rf /home/ga/DICOM/anonymized/ 2>/dev/null || true

# Verify sample DICOM files exist or create them
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_COUNT=$(find "$SAMPLE_DIR" -type f -name "*.dcm" 2>/dev/null | wc -l)

if [ "$DICOM_COUNT" -eq 0 ]; then
    echo "No DICOM samples found, creating synthetic ones..."
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    study_uid = generate_uid()
    series_uid = generate_uid()

    for i in range(5):
        filename = os.path.join(sample_dir, f"CT_slice_{i+1:03d}.dcm")
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "Test^Patient"
        ds.PatientID = "TEST001"
        ds.PatientBirthDate = "19800101"
        ds.PatientSex = "O"
        ds.StudyDescription = "Sample CT Study"
        ds.SeriesDescription = "Sample CT Series"
        ds.InstanceNumber = i + 1
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.Rows = 256
        ds.Columns = 256
        ds.BitsAllocated = 16
        ds.BitsStored = 12
        ds.HighBit = 11
        ds.PixelRepresentation = 0
        ds.RescaleIntercept = -1024
        ds.RescaleSlope = 1
        ds.WindowCenter = 40
        ds.WindowWidth = 400

        image = np.zeros((256, 256), dtype=np.uint16)
        center = 128
        for r in range(256):
            for c in range(256):
                image[r, c] = int((r + c) * 4000 / 512)
                dist = ((r - center)**2 + (c - center)**2) ** 0.5
                if dist < 60:
                    image[r, c] = 2000 + i * 100

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")
except Exception as e:
    print(f"Error creating synthetic DICOM: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
fi

# Ensure Weasis is stopped before launching
pkill -f weasis > /dev/null 2>&1 || true
sleep 2

# Launch Weasis and open the sample directory
FIRST_DCM=$(find /home/ga/DICOM/samples -type f -name "*.dcm" | head -1)
if [ -n "$FIRST_DCM" ]; then
    DICOM_DIR=$(dirname "$FIRST_DCM")
    echo "Loading DICOM directory: $DICOM_DIR"
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '\$dicom:get -l \"$DICOM_DIR\"' > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis '\$dicom:get -l \"$DICOM_DIR\"' > /tmp/weasis_ga.log 2>&1 &"
    sleep 10
else
    echo "Starting Weasis without pre-loading (fallback)..."
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &"
    sleep 8
fi

# Wait for Weasis window
wait_for_weasis 60

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_weasis 2>/dev/null || true

# Dismiss any startup dialogs
dismiss_first_run_dialog
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="