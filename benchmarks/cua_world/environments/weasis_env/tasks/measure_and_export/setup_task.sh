#!/bin/bash
echo "=== Setting up measure_and_export task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is clean
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/annotated_measurement.jpg" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Locate available DICOM files
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Fallback: create synthetic DICOM if samples are missing
if [ -z "$DICOM_FILE" ]; then
    echo "Creating fallback sample DICOM file..."
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
        ds.PatientName = "Measure^Test"
        ds.PatientID = "MEASURE001"
        ds.StudyDescription = "Measurement Export Test"
        
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
        image[:, :] = 500
        # Add a circular structure to measure
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.2:
                    image[i, j] = 2000
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created fallback: {filename}")
        
    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "measure_test.dcm"))
except Exception as e:
    print(f"Error creating fallback: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/measure_test.dcm"
fi

echo "Using DICOM file: $DICOM_FILE"

# Kill any existing Weasis instances
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis to fully load
wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Maximize and focus
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Wait a bit more for UI to settle and take initial screenshot
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="