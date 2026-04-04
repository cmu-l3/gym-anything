#!/bin/bash
echo "=== Setting up adjust_window_level task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure DICOM samples exist
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=""

# Find or create a DICOM file
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

if [ -z "$DICOM_FILE" ]; then
    echo "Creating sample DICOM file..."
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, modality="CT", size=512):
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
        ds.PatientName = "WindowLevel^Test"
        ds.PatientID = "WL001"
        ds.PatientBirthDate = "19700101"
        ds.PatientSex = "O"
        ds.StudyDescription = "Window Level Test Study"
        ds.SeriesDescription = "Chest CT Series"

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
        # Standard CT window preset
        ds.WindowCenter = 40
        ds.WindowWidth = 400

        # Create more complex image for window/level testing
        image = np.zeros((size, size), dtype=np.uint16)
        # Background (air)
        image[:, :] = 0
        # Soft tissue region
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.4:
                    image[i, j] = 1000 + int(np.random.normal(40, 10))
        # Bone-like region (higher density)
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.15:
                    image[i, j] = 2500 + int(np.random.normal(0, 50))
        # Some variation
        noise = np.random.normal(0, 20, (size, size)).astype(np.int16)
        image = np.clip(image.astype(np.int32) + noise, 0, 4095).astype(np.uint16)

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "chest_ct.dcm"), modality="CT", size=512)

except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/chest_ct.dcm"
fi

echo "DICOM file: $DICOM_FILE"

# Record initial window/level values
python3 << PYEOF > /tmp/initial_wl.json
import json
try:
    import pydicom
    ds = pydicom.dcmread("$DICOM_FILE")
    wc = float(ds.WindowCenter) if hasattr(ds, 'WindowCenter') else 40
    ww = float(ds.WindowWidth) if hasattr(ds, 'WindowWidth') else 400
    print(json.dumps({"window_center": wc, "window_width": ww}))
except Exception as e:
    print(json.dumps({"window_center": 40, "window_width": 400, "error": str(e)}))
PYEOF
cat /tmp/initial_wl.json

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis with DICOM file..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis to load
wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait a bit more for UI to settle
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "A CT image is loaded in Weasis"
echo "Initial Window Center: $(cat /tmp/initial_wl.json | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"window_center\", 40))')"
echo "Initial Window Width: $(cat /tmp/initial_wl.json | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"window_width\", 400))')"
echo "Use the Window/Level tool to adjust the display"
