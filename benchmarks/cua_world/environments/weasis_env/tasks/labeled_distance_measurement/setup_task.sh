#!/bin/bash
echo "=== Setting up labeled_distance_measurement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is empty
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/labeled_vessel.png 2>/dev/null || true
chown ga:ga "$EXPORT_DIR"
chmod 755 "$EXPORT_DIR"

# Find a DICOM file to load (prefer real CT sample, then MR, then synthetic)
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR/ct_scan" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

if [ -z "$DICOM_FILE" ]; then
    DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
fi

# Fallback synthetic generation if absolutely nothing exists
if [ -z "$DICOM_FILE" ]; then
    echo "No real DICOM found, generating synthetic fallback..."
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    filename = "/home/ga/DICOM/samples/synthetic/vessel_test.dcm"
    size = 512
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
    ds.PatientName = "Vessel^Test"
    ds.PatientID = "VES001"
    
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
    image[:, :] = 200  # background
    center = size // 2
    # Create a bright central circle to simulate an aorta
    for i in range(size):
        for j in range(size):
            dist = np.sqrt((i - center)**2 + (j - center)**2)
            if dist < size * 0.15:
                image[i, j] = 1500
            elif dist < size * 0.35:
                image[i, j] = 800
    ds.PixelData = image.tobytes()
    ds.save_as(filename)
    print(f"Created synthetic DICOM: {filename}")
except Exception as e:
    print(f"Error creating fallback DICOM: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="/home/ga/DICOM/samples/synthetic/vessel_test.dcm"
fi

echo "Selected DICOM file: $DICOM_FILE"

# Make sure Weasis is not running (fresh start)
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to start and maximize
wait_for_weasis 60
sleep 5

# Maximize Weasis
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait for UI to settle and take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="