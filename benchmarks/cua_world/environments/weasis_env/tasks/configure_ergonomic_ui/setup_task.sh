#!/bin/bash
echo "=== Setting up configure_ergonomic_ui task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Clean up any pre-existing files
rm -f "$EXPORT_DIR/ergonomic_ui.png" 2>/dev/null || true
rm -f "$EXPORT_DIR/ui_settings.txt" 2>/dev/null || true

# Prepare standard preferences (Light theme, default font size) to ensure known starting state
mkdir -p /home/ga/.weasis
cat > /home/ga/.weasis/weasis.properties << 'PREFSEOF'
weasis.confirm.closing=false
weasis.show.startup.tips=false
weasis.look=com.formdev.flatlaf.FlatLightLaf
weasis.font.size=12
PREFSEOF
chown -R ga:ga /home/ga/.weasis

mkdir -p /home/ga/snap/weasis/current/.weasis 2>/dev/null || true
cp /home/ga/.weasis/weasis.properties /home/ga/snap/weasis/current/.weasis/weasis.properties 2>/dev/null || true
chown -R ga:ga /home/ga/snap 2>/dev/null || true

# Prepare DICOM
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

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
    
    filename = "/home/ga/DICOM/samples/synthetic/sample_ct.dcm"
    size = 256
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
    ds.PatientName = "Theme^Test"
    ds.PatientID = "THM001"
    
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
    for i in range(size):
        for j in range(size):
            if (i - 128)**2 + (j - 128)**2 < 64**2:
                image[i, j] = 2000
                
    ds.PixelData = image.tobytes()
    ds.save_as(filename)
    print(f"Created: {filename}")
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/sample_ct.dcm"
fi

pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog
sleep 2

WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="