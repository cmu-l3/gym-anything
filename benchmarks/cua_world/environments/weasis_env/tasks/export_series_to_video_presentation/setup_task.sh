#!/bin/bash
echo "=== Setting up export_series_to_video_presentation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean export directory
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/anatomy_scroll.* 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Identify the dataset to use (prefer real downloaded CT scan)
SAMPLE_DIR="/home/ga/DICOM/samples/ct_scan"
if [ ! -d "$SAMPLE_DIR" ] || [ -z "$(ls -A $SAMPLE_DIR 2>/dev/null)" ]; then
    echo "Real CT scan missing, falling back to synthetic series..."
    SAMPLE_DIR="/home/ga/DICOM/samples/synthetic_series"
    mkdir -p "$SAMPLE_DIR"
    
    # Generate multi-slice synthetic DICOM if real one isn't available
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, z_index, total_slices=20, size=256):
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        ds.StudyInstanceUID = "1.2.3.4.5.6.7"
        ds.SeriesInstanceUID = "1.2.3.4.5.6.7.8"
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "VideoExport^Patient"
        ds.PatientID = "VID001"
        ds.StudyDescription = "Multi-slice CT Series"
        ds.SeriesDescription = "Axial"
        ds.InstanceNumber = z_index
        ds.SliceLocation = float(z_index * 2.0)

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
        image[:, :] = 100  # background
        center = size // 2
        # Variable radius to simulate anatomical changes across slices
        radius = 30 + int(50 * np.sin(np.pi * z_index / total_slices))
        for i in range(size):
            for j in range(size):
                if (i - center)**2 + (j - center)**2 < radius**2:
                    image[i, j] = 1500
                elif (i - center)**2 + (j - center)**2 < (radius + 20)**2:
                    image[i, j] = 800

        ds.PixelData = image.tobytes()
        ds.save_as(filename)

    for i in range(1, 21):
        create_sample_dicom(os.path.join("/home/ga/DICOM/samples/synthetic_series", f"slice_{i:03d}.dcm"), i, 20)
    print("Created 20 synthetic slices.")
except Exception as e:
    print(f"Error creating synthetic dicoms: {e}")
PYEOF
fi

chown -R ga:ga "$SAMPLE_DIR"

# Kill any existing Weasis
pkill -f weasis >/dev/null 2>&1 || true
sleep 2

# Launch Weasis loading the entire directory (loads as a series)
echo "Launching Weasis with DICOM series..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to appear and load
wait_for_weasis 60
sleep 5

# Dismiss first-run dialog
dismiss_first_run_dialog
sleep 2

# Maximize Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_weasis 2>/dev/null || true

# Give time for the multi-slice volume to fully load
sleep 5

# Take initial screenshot showing loaded state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="