#!/bin/bash
echo "=== Setting up configure_display_prefs task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Setup directories
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"

# Clear any previous exports to prevent false positives
rm -f "$EXPORT_DIR/prefs_changes.txt" 2>/dev/null || true
rm -f "$EXPORT_DIR/prefs_verification.png" 2>/dev/null || true

# Generate a synthetic DICOM file if it doesn't exist
DICOM_FILE="$SAMPLE_DIR/ct_prefs_test.dcm"
if [ ! -f "$DICOM_FILE" ]; then
    echo "Creating sample DICOM file..."
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
        ds.PatientName = "Prefs^Test"
        ds.PatientID = "PREF001"
        ds.StudyDescription = "Preferences Configuration Test"
        
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
        
        # Create a basic image pattern
        image = np.zeros((size, size), dtype=np.uint16)
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.4:
                    image[i, j] = 1000 + int((i+j)%100) # Add some texture
                else:
                    image[i, j] = 100
        
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created DICOM: {filename}")

    create_sample_dicom("/home/ga/DICOM/samples/synthetic/ct_prefs_test.dcm")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF
fi

chown -R ga:ga "/home/ga/DICOM"
chmod -R 777 "$EXPORT_DIR"

# Pre-record the state of Weasis config files
WEASIS_PREFS_DIR="/home/ga/.weasis"
SNAP_PREFS_DIR="/home/ga/snap/weasis/current/.weasis"
find "$WEASIS_PREFS_DIR" "$SNAP_PREFS_DIR" -type f \( -name "*.xml" -o -name "*.properties" \) -exec cat {} + 2>/dev/null > /tmp/initial_weasis_configs.txt

# Ensure Weasis is stopped
pkill -f weasis 2>/dev/null || true
sleep 2

# Start Weasis with the DICOM file
echo "Starting Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to load
wait_for_weasis 60
sleep 5
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="