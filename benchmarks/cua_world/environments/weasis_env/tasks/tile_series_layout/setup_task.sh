#!/bin/bash
echo "=== Setting up tile_series_layout task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
SERIES_DIR="/home/ga/DICOM/samples/multi_slice"

# Ensure export directory exists and is clean
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
rm -f "$EXPORT_DIR/grid_layout.png"

# Ensure a proper multi-slice DICOM series exists
mkdir -p "$SERIES_DIR"
echo "Generating synthetic multi-slice DICOM series..."
python3 << 'PYEOF'
import os
import numpy as np

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_series(directory, num_slices=6, size=256):
        series_uid = generate_uid()
        study_uid = generate_uid()
        
        for i in range(num_slices):
            filename = os.path.join(directory, f"slice_{i+1:03d}.dcm")
            
            file_meta = Dataset()
            file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2' # CT Image Storage
            file_meta.MediaStorageSOPInstanceUID = generate_uid()
            file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

            ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)

            dt = datetime.datetime.now()
            ds.ContentDate = dt.strftime('%Y%m%d')
            ds.ContentTime = dt.strftime('%H%M%S.%f')
            ds.StudyInstanceUID = study_uid
            ds.SeriesInstanceUID = series_uid
            ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
            ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
            ds.Modality = "CT"
            ds.PatientName = "Grid^Test"
            ds.PatientID = "GRID001"
            ds.StudyDescription = "Grid Layout Test Study"
            ds.SeriesDescription = "Multi-slice Series"
            ds.InstanceNumber = i + 1
            ds.SliceLocation = float(i * 5.0)

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

            # Create visual variation between slices so tiling is obvious
            image = np.zeros((size, size), dtype=np.uint16)
            center = size // 2
            radius = (size // 4) + (i * 5) # Growing circle per slice
            
            for y in range(size):
                for x in range(size):
                    if (y - center)**2 + (x - center)**2 < radius**2:
                        image[y, x] = 1000 + (i * 100)
            
            # Add slice number visually (rough block)
            for y in range(10, 30):
                for x in range(10, 10 + (i+1)*10):
                    image[y, x] = 2000

            ds.PixelData = image.tobytes()
            ds.save_as(filename)

        print(f"Created {num_slices} slices in {directory}")

    create_series("/home/ga/DICOM/samples/multi_slice", num_slices=6)

except Exception as e:
    print(f"Error creating series: {e}")
PYEOF
chown -R ga:ga "$SERIES_DIR"

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the directory (loads all slices as a series)
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SERIES_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SERIES_DIR' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Maximize Weasis
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Wait a bit more for UI to settle
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="