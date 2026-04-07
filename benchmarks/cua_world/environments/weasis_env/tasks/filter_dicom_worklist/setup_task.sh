#!/bin/bash
echo "=== Setting up filter_dicom_worklist task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Target Directories
TRAUMA_DIR="/home/ga/DICOM/trauma_transfer"
EXPORT_DIR="/home/ga/DICOM/exports"

# Clean up any old files from previous runs
rm -rf "$TRAUMA_DIR" 2>/dev/null || true
rm -f "$EXPORT_DIR/target_patient.png" 2>/dev/null || true

mkdir -p "$TRAUMA_DIR"
mkdir -p "$EXPORT_DIR"

echo "Generating obfuscated DICOM files..."
python3 << 'PYEOF'
import os
import uuid
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_dicom(filename, pat_id, is_target, size=512):
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
        ds.PatientName = f"Patient^{pat_id}"
        ds.PatientID = pat_id
        ds.StudyDescription = "Trauma Transfer"
        
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
        if is_target:
            # Cross pattern payload (verifiable target)
            image[:, :] = 500
            image[size//2-20:size//2+20, :] = 3000
            image[:, size//2-20:size//2+20] = 3000
        else:
            # Distractor gradient
            for i in range(size):
                for j in range(size):
                    image[i, j] = int((i + j) * 4000 / (2 * size))
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)

    out_dir = "/home/ga/DICOM/trauma_transfer"
    for i in range(1, 11):
        is_target = (i == 7)
        pat_id = "TRAUMA-007" if is_target else f"TRAUMA-{i:03d}"
        fname = os.path.join(out_dir, f"{uuid.uuid4().hex}.dcm")
        create_dicom(fname, pat_id, is_target)
    print("Successfully generated 10 obfuscated DICOM files.")
except Exception as e:
    print(f"Error generating DICOM files: {e}")
PYEOF

chown -R ga:ga "$TRAUMA_DIR"
chown -R ga:ga "$EXPORT_DIR"
chmod -R 755 "$TRAUMA_DIR"
chmod -R 777 "$EXPORT_DIR"

# Make sure Weasis is not running (fresh start)
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis completely empty
echo "Starting Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait a bit more for UI to settle
sleep 2

# Maximize Weasis for the agent
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true
sleep 1

# Take initial screenshot proving empty viewer & setup complete
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="