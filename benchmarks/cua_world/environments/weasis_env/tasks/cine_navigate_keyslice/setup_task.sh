#!/bin/bash
echo "=== Setting up cine_navigate_keyslice task ==="
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create unique slices for this task
CINE_DIR="/home/ga/DICOM/samples/synthetic_cine"
mkdir -p "$CINE_DIR"
chown ga:ga "$CINE_DIR"

echo "Generating synthetic 5-slice CT series..."
python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_slice(filename, idx, size=256):
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
        
        ds.ContentDate = datetime.datetime.now().strftime('%Y%m%d')
        ds.ContentTime = datetime.datetime.now().strftime('%H%M%S.%f')
        ds.StudyInstanceUID = "1.2.3.4.5.6.7"
        ds.SeriesInstanceUID = "1.2.3.4.5.6.7.8"
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "Cine^Navigate"
        ds.PatientID = "CINE001"
        ds.StudyDescription = "Navigation Test Study"
        ds.SeriesDescription = "5-Slice Series"
        ds.InstanceNumber = idx
        ds.SliceLocation = float(idx * 5.0)
        
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
        
        # Background gradient
        for i in range(size):
            for j in range(size):
                image[i, j] = int((i + j) * 2000 / (2 * size))
        
        # A moving circle that changes radius based on slice
        center_y = size // 2
        center_x = size // 2
        radius = 20 + (idx * 10)
        for i in range(size):
            for j in range(size):
                if (i - center_y)**2 + (j - center_x)**2 < radius**2:
                    image[i, j] = 2000 + (idx * 100)
                    
        # Add a slice identifier block
        block_x = 10 + (idx * 30)
        image[10:40, block_x:block_x+30] = 3000
        
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        
    for i in range(1, 6):
        create_slice(f"/home/ga/DICOM/samples/synthetic_cine/CT_slice_{i:03d}.dcm", i)
except Exception as e:
    print(f"Error creating dicom: {e}")
PYEOF

chown -R ga:ga "$CINE_DIR"
chmod -R 755 "$CINE_DIR"

# Clear any previous exports
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/key_slice.png" "$EXPORT_DIR/slice_info.txt" 2>/dev/null || true
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Launch Weasis
echo "Restarting Weasis..."
pkill -f weasis 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /snap/bin/weasis '$CINE_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$CINE_DIR' > /tmp/weasis_ga.log 2>&1 &"

sleep 8
wait_for_weasis 60
sleep 2
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_start.png
echo "=== Setup complete ==="