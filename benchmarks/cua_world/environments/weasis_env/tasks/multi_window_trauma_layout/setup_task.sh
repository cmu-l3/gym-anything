#!/bin/bash
echo "=== Setting up multi_window_trauma_layout task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create specific directory for this task to avoid ambiguity
TARGET_DIR="/home/ga/DICOM/samples/trauma_ct"
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$TARGET_DIR"
mkdir -p "$EXPORT_DIR"

# Clean any existing artifacts
rm -f "$EXPORT_DIR/trauma_layout.png" 2>/dev/null
rm -f "$EXPORT_DIR/window_levels.txt" 2>/dev/null

# Populate the target directory with a CT series
# The weasis_env setup script downloads samples or generates synthetic ones.
if [ -d "/home/ga/DICOM/samples/ct_scan" ] && [ "$(ls -A /home/ga/DICOM/samples/ct_scan 2>/dev/null)" ]; then
    echo "Using real CT scan samples..."
    cp -r /home/ga/DICOM/samples/ct_scan/* "$TARGET_DIR/"
elif [ -d "/home/ga/DICOM/samples/synthetic" ] && [ "$(ls -A /home/ga/DICOM/samples/synthetic 2>/dev/null)" ]; then
    echo "Using synthetic CT scan samples..."
    cp -r /home/ga/DICOM/samples/synthetic/* "$TARGET_DIR/"
else
    echo "Creating fallback DICOM files..."
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, size=256):
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
        ds.PatientName = "Trauma^Patient"
        ds.PatientID = "TRAUMA001"
        ds.StudyDescription = "Trauma CT"
        
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

        # Create gradient and circle for varied density
        image = np.zeros((size, size), dtype=np.uint16)
        for i in range(size):
            for j in range(size):
                image[i, j] = int((i + j) * 4000 / (2 * size))
        center = size // 2
        radius = size // 4
        for i in range(size):
            for j in range(size):
                if (i - center)**2 + (j - center)**2 < radius**2:
                    image[i, j] = 2000

        ds.PixelData = image.tobytes()
        ds.save_as(filename)

    for i in range(3):
        create_sample_dicom(os.path.join("/home/ga/DICOM/samples/trauma_ct", f"CT_slice_{i+1:03d}.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
fi

# Ensure correct permissions
chown -R ga:ga "$TARGET_DIR"
chown -R ga:ga "$EXPORT_DIR"
chmod -R 755 "$TARGET_DIR"
chmod -R 777 "$EXPORT_DIR"

# Launch Weasis if not running
if ! is_weasis_running; then
    echo "Launching Weasis..."
    su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
    sleep 8
    wait_for_weasis 60
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Maximize and focus the window
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi
sleep 2

# Take initial screenshot showing clean UI before agent acts
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="