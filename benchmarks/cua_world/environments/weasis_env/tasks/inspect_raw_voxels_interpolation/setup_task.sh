#!/bin/bash
echo "=== Setting up inspect_raw_voxels_interpolation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
SAMPLE_DIR="/home/ga/DICOM/samples"
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"

# Clean up any previous export
rm -f "$EXPORT_DIR/nearest_neighbor.png" 2>/dev/null || true

# Always generate a fresh noisy synthetic DICOM to guarantee no natural flat regions
SYNTHETIC_DIR="$SAMPLE_DIR/synthetic_noisy"
mkdir -p "$SYNTHETIC_DIR"
export DICOM_FILE_PATH="$SYNTHETIC_DIR/noisy_ct.dcm"

echo "Creating synthetic DICOM file with noise..."
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
        ds.PatientName = "Voxel^Test"
        ds.PatientID = "VOX001"
        ds.StudyDescription = "Voxel Interpolation Test"

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
        for i in range(size):
            for j in range(size):
                image[i, j] = 500 + int((i + j) * 1000 / (2 * size))
        
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if dist < size * 0.3:
                    image[i, j] += 1000
                if dist < size * 0.1:
                    image[i, j] += 1000
                    
        # Seed and add noise to guarantee no naturally identical adjacent pixels
        np.random.seed(42)
        noise = np.random.normal(0, 50, (size, size)).astype(np.int16)
        image = np.clip(image.astype(np.int32) + noise, 0, 4095).astype(np.uint16)

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created noisy DICOM: {filename}")

    create_sample_dicom(os.environ.get('DICOM_FILE_PATH'))
except Exception as e:
    print(f"Error: {e}")
PYEOF

chown -R ga:ga "$SAMPLE_DIR"

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the noisy DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE_PATH' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE_PATH' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Maximize and focus Weasis window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Wait a bit more for UI to settle
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="