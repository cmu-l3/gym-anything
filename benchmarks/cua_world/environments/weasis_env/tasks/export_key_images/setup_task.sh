#!/bin/bash
echo "=== Setting up export_key_images task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup Data Directory
SERIES_DIR="/home/ga/DICOM/samples/multi_slice_ct"
EXPORT_DIR="/home/ga/DICOM/exports/key_images"

# Clean any previous state
rm -rf "$SERIES_DIR"
rm -rf "$EXPORT_DIR"
mkdir -p "$SERIES_DIR"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$SERIES_DIR" "$EXPORT_DIR"

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_export_count

# 3. Prepare a 10-slice DICOM Series
# We use Python/pydicom to generate a controlled 10-slice CT series if a real one isn't cleanly available.
# We will draw explicit text numbers on them using PIL to ensure slices are distinct.
echo "Generating 10-slice DICOM series..."
python3 << 'PYEOF'
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

try:
    import pydicom
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_slice(filename, slice_num, total_slices=10, size=512):
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2' # CT Image
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)

        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        
        # Keep same Study/Series UID to group them in Weasis
        ds.StudyInstanceUID = "1.2.3.4.5.6.7.8.9.0.1" 
        ds.SeriesInstanceUID = "1.2.3.4.5.6.7.8.9.0.2"
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "KeyImage^Patient"
        ds.PatientID = "KEY001"
        ds.StudyDescription = "Key Image Export Study"
        ds.SeriesDescription = "Chest CT 10-Slice"
        
        # Positional metadata
        ds.InstanceNumber = slice_num
        ds.SliceLocation = float(slice_num * 5.0)

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

        # Create image with slice number clearly drawn
        img_pil = Image.new('I', (size, size), 0)
        draw = ImageDraw.Draw(img_pil)
        
        # Draw background shapes to simulate anatomy
        center = size // 2
        radius = int((size // 3) * (1 - 0.2 * abs(slice_num - total_slices/2)/(total_slices/2)))
        draw.ellipse([center-radius, center-radius, center+radius, center+radius], fill=1000)
        
        # Draw explicit slice number
        # We don't have a guaranteed font, so we draw basic lines for the number, or use default font
        try:
            draw.text((50, 50), f"SLICE {slice_num}", fill=2500)
            draw.text((center-40, center), f"{slice_num}", fill=2500)
        except:
            pass # Fallback if font fails

        image_np = np.array(img_pil, dtype=np.uint16)
        ds.PixelData = image_np.tobytes()
        ds.save_as(filename)

    series_dir = "/home/ga/DICOM/samples/multi_slice_ct"
    for i in range(1, 11):
        create_slice(os.path.join(series_dir, f"slice_{i:02d}.dcm"), i)
    print("Successfully created 10 DICOM slices.")
except Exception as e:
    print(f"Error creating DICOM files: {e}")
PYEOF
chown -R ga:ga "$SERIES_DIR"

# 4. Ensure Weasis is closed, then launch
pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SERIES_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SERIES_DIR' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis UI
wait_for_weasis 60
sleep 2

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss first-run dialog
sleep 2
dismiss_first_run_dialog

# Wait for images to load into viewer
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "CT Series loaded. Awaiting agent to bookmark and export."