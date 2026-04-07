#!/bin/bash
echo "=== Setting up configure_external_pacs_node task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any existing state/artifacts to prevent false positives
rm -f /home/ga/Desktop/pacs_node_config.png 2>/dev/null || true

# Remove any existing REGIONAL_ARCHIVE entries from Weasis configs
find /home/ga/.weasis /home/ga/snap/weasis -type f -name "*.xml" -exec sed -i '/REGIONAL_ARCHIVE/d' {} + 2>/dev/null || true
find /home/ga/.weasis /home/ga/snap/weasis -type f -name "*.properties" -exec sed -i '/REGIONAL_ARCHIVE/d' {} + 2>/dev/null || true

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure a sample DICOM exists to launch Weasis into a clinical context
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# If no DICOM exists, generate a basic one using pydicom fallback
if [ -z "$DICOM_FILE" ]; then
    echo "Creating sample DICOM file..."
    mkdir -p "$SAMPLE_DIR/synthetic"
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
        ds.PatientName = "Network^Setup"
        ds.PatientID = "NET001"
        ds.StudyDescription = "PACS Node Configuration Task"
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
        image[:, :] = 1000
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
    
    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "network_test.dcm"))
except Exception as e:
    pass
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/network_test.dcm"
fi

# 4. Make sure Weasis is not running from a previous state
pkill -f weasis 2>/dev/null || true
sleep 2

# 5. Launch Weasis
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for UI
wait_for_weasis 60
sleep 2

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="