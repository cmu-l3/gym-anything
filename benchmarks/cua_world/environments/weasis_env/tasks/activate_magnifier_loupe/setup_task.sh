#!/bin/bash
echo "=== Setting up activate_magnifier_loupe task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
EXPECTED_OUTPUT="$EXPORT_DIR/lens_active.png"

# Clean up any previous attempts
mkdir -p "$EXPORT_DIR"
rm -f "$EXPECTED_OUTPUT" 2>/dev/null || true
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Locate a DICOM sample file (Environment pre-downloads real Rubo samples)
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Fallback to creating a synthetic one if the download failed in the base image
if [ -z "$DICOM_FILE" ]; then
    echo "Sample not found, creating synthetic fallback DICOM..."
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
        
        ds.ContentDate = datetime.datetime.now().strftime('%Y%m%d')
        ds.ContentTime = datetime.datetime.now().strftime('%H%M%S.%f')
        ds.StudyInstanceUID = generate_uid()
        ds.SeriesInstanceUID = generate_uid()
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "Loupe^Test"
        ds.PatientID = "LOUPE001"
        ds.StudyDescription = "Magnifier Tool Test"
        
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
        
        # Create image with specific details so magnification is obvious
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 500
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.3:
                    # Add distinct rings so zooming looks visually distinct
                    image[i, j] = 1000 + int(np.sin(dist/5) * 500)
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
    
    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "loupe_test.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/loupe_test.dcm"
fi

# Ensure Weasis isn't already running in a bad state
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis with $DICOM_FILE..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application window to appear
wait_for_weasis 60
sleep 5

# Maximize Weasis for optimal agent visibility
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Final refocus
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Take initial state screenshot for trajectory evidence
take_screenshot /tmp/task_start.png
echo "Captured initial state."

echo "=== Task setup complete ==="