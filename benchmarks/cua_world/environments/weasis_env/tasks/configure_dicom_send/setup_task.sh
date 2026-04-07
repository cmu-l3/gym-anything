#!/bin/bash
echo "=== Setting up configure_dicom_send task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare PACS receiver directory and logs
RECEIVER_DIR="/tmp/pacs_received"
mkdir -p "$RECEIVER_DIR"
chmod 777 "$RECEIVER_DIR"
rm -f "$RECEIVER_DIR"/*
rm -f /tmp/storescp.log

# 2. Start the simulated PACS (storescp from dcmtk)
# -d enables debug logging (crucial for catching Association/C-STORE events)
echo "Starting storescp on port 4242..."
pkill -f storescp 2>/dev/null || true
su - ga -c "storescp -d -od $RECEIVER_DIR 4242 > /tmp/storescp.log 2>&1 &"
sleep 2

if ! pgrep -f storescp > /dev/null; then
    echo "WARNING: storescp failed to start! DICOM receiver is offline."
else
    echo "storescp is running in the background."
fi

# 3. Create a reliable synthetic DICOM file for the task
SAMPLE_DIR="/home/ga/DICOM/samples/send_test"
mkdir -p "$SAMPLE_DIR"
echo "Creating sample DICOM..."
python3 << 'PYEOF'
import os
import numpy as np
import datetime
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    
    filename = "/home/ga/DICOM/samples/send_test/image.dcm"
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2' # CT Image Storage
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
    ds.PatientName = "Network^SendTest"
    ds.PatientID = "NET001"
    ds.StudyDescription = "DICOM Send Test Study"
    ds.SeriesDescription = "Primary Series"
    
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = 256
    ds.Columns = 256
    ds.BitsAllocated = 16
    ds.BitsStored = 12
    ds.HighBit = 11
    ds.PixelRepresentation = 0
    ds.PixelData = np.full((256, 256), 1000, dtype=np.uint16).tobytes()
    
    ds.save_as(filename)
    print("Sample DICOM created successfully.")
except Exception as e:
    print(f"Error creating DICOM: {e}")
PYEOF
chown -R ga:ga "$SAMPLE_DIR"

# 4. Record task start time (Anti-gaming check)
date +%s > /tmp/task_start_time.txt

# 5. Launch Weasis with the sample directory
pkill -f weasis 2>/dev/null || true
sleep 1

echo "Launching Weasis..."
if command -v /snap/bin/weasis &> /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &"
fi

# Wait for Weasis to load
wait_for_weasis 60
sleep 4

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# 6. Focus and Maximize Weasis for the agent
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="