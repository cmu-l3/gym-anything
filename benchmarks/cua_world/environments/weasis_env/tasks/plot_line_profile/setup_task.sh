#!/bin/bash
echo "=== Setting up plot_line_profile task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure exports directory exists and is clean
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
rm -f "$EXPORT_DIR/line_profile_analysis.png"

# Ensure DICOM samples exist
SAMPLE_DIR="/home/ga/DICOM/samples"
mkdir -p "$SAMPLE_DIR/synthetic"
chown ga:ga "$SAMPLE_DIR/synthetic"

DICOM_FILE="$SAMPLE_DIR/synthetic/profile_test.dcm"

# Always create a fresh test DICOM with a distinct bright center for this task
echo "Creating sample DICOM file with dense structures..."
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
        ds.PatientName = "Profile^Test"
        ds.PatientID = "PROF001"
        ds.StudyDescription = "Line Profile Test Study"

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

        # Create image with a distinct bright central structure and softer background
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
        # Dense bone-like region in center for the profile peak
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.1:
                    image[i, j] = 2500 + int(np.random.normal(0, 30))
        
        # Add a secondary dense spot to make it interesting
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - (center-100))**2 + (j - (center+100))**2)
                if dist < size * 0.05:
                    image[i, j] = 1800
                    
        # Some baseline noise
        noise = np.random.normal(0, 15, (size, size)).astype(np.int16)
        image = np.clip(image.astype(np.int32) + noise, 0, 4095).astype(np.uint16)

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    create_sample_dicom("/home/ga/DICOM/samples/synthetic/profile_test.dcm")

except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF
chown ga:ga "$DICOM_FILE"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "weasis"; then
        echo "Weasis window detected"
        break
    fi
    sleep 2
done

# Focus and Maximize Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true
sleep 1

# Dismiss first-run dialog if it appears
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
sleep 2

# Take initial screenshot showing the loaded image
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="