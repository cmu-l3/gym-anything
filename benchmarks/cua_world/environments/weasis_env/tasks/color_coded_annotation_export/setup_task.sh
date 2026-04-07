#!/bin/bash
echo "=== Setting up color_coded_annotation_export task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean export directory
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
rm -f "$EXPORT_DIR/urgent_finding.jpg" 2>/dev/null || true

# Prepare sample directory
SAMPLE_DIR="/home/ga/DICOM/samples"
mkdir -p "$SAMPLE_DIR/synthetic"
DICOM_FILE="$SAMPLE_DIR/synthetic/urgent_case.dcm"

# Generate the custom DICOM file with a clear "finding" to annotate
echo "Generating custom DICOM case..."
python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    filename = "/home/ga/DICOM/samples/synthetic/urgent_case.dcm"
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
    ds.PatientName = "Urgent^Case"
    ds.PatientID = "URG001"
    ds.StudyDescription = "Urgent Finding CT"
    
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

    # Draw the image data
    image = np.zeros((size, size), dtype=np.uint16)
    image[:, :] = 200 # Background
    center = size // 2
    
    # Soft tissue anatomy
    for i in range(size):
        for j in range(size):
            dist = np.sqrt((i - center)**2 + (j - center)**2)
            if dist < size * 0.35:
                image[i, j] = 1040 
    
    # The "Urgent Finding" (A highly bright distinct spot)
    finding_cx, finding_cy = center + 60, center - 60
    for i in range(size):
        for j in range(size):
            dist = np.sqrt((i - finding_cy)**2 + (j - finding_cx)**2)
            if dist < 15:
                image[i, j] = 2800 # Hyperdense lesion

    ds.PixelData = image.tobytes()
    ds.save_as(filename)
    print(f"Created DICOM: {filename}")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF

chown -R ga:ga "$SAMPLE_DIR"

# Ensure clean state for Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the target DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60
sleep 2

# Clear any first time dialogs
dismiss_first_run_dialog
sleep 2

# Maximize and Focus window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

sleep 1
# Capture initial screenshot as baseline evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="