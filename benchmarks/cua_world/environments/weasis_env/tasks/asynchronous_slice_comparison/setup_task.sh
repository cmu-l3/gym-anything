#!/bin/bash
echo "=== Setting up asynchronous_slice_comparison task ==="

source /workspace/scripts/task_utils.sh

# Ensure export dir exists and is clean
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
rm -f "$EXPORT_DIR/async_comparison.png" 2>/dev/null || true
rm -f "$EXPORT_DIR/task_complete.txt" 2>/dev/null || true

# Ensure we have a multi-slice series explicitly prepared
SAMPLE_DIR="/home/ga/DICOM/samples/synthetic"
mkdir -p "$SAMPLE_DIR"

python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, slice_num, total_slices=10, size=256):
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
        
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        
        # Consistent study/series UIDs so Weasis groups them correctly
        ds.StudyInstanceUID = "1.2.3.4.5.6.7.8.9.1"
        ds.SeriesInstanceUID = "1.2.3.4.5.6.7.8.9.2"
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        
        ds.Modality = "CT"
        ds.PatientName = "Async^Comparison"
        ds.PatientID = "ASYNC001"
        ds.StudyDescription = "Multi-slice CT"
        ds.SeriesDescription = "Axial Series"
        ds.InstanceNumber = slice_num
        
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
        
        # Create an image that physically moves the anatomy to make slice diffs obvious
        image = np.zeros((size, size), dtype=np.uint16)
        center_x = size // 2
        center_y = int(size * (slice_num / total_slices))
        for i in range(size):
            for j in range(size):
                if (i - center_y)**2 + (j - center_x)**2 < 40**2:
                    image[i, j] = 2000
                else:
                    image[i, j] = 500
        
        ds.PixelData = image.tobytes()
        ds.save_as(filename)

    for i in range(1, 11):
        create_sample_dicom(os.path.join("/home/ga/DICOM/samples/synthetic", f"async_ct_{i:03d}.dcm"), i)
except Exception as e:
    print(f"Error: {e}")
PYEOF

chown -R ga:ga "$SAMPLE_DIR"
date +%s > /tmp/task_start_time.txt

pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis loading the whole synthetic directory
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60
sleep 2
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

sleep 1
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="