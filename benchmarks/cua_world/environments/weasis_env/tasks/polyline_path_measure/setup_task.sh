#!/bin/bash
echo "=== Setting up polyline_path_measure task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Prepare output directory and ensure clean state
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/polyline_report.txt" "$EXPORT_DIR/polyline_screenshot.png" 2>/dev/null
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Ensure DICOM samples exist
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

# Generate a synthetic DICOM if no samples exist
if [ -z "$DICOM_FILE" ]; then
    echo "Creating synthetic DICOM sample..."
    mkdir -p "$SAMPLE_DIR/synthetic"
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
        ds.PatientName = "Polyline^Test"
        ds.PatientID = "POLY001"
        ds.StudyDescription = "Polyline Measurement Test"
        
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
        ds.PixelSpacing = [1.0, 1.0]  # Needed for mm measurements

        # Create gradient with distinct boundaries for tracing
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 500
        center = size // 2
        for i in range(size):
            for j in range(size):
                dist = np.sqrt((i - center)**2 + (j - center)**2)
                if 100 < dist < 120:  # A curved ring structure to trace
                    image[i, j] = 2000
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
    
    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "structure_scan.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/structure_scan.dcm"
fi

# Make sure Weasis isn't already running in wrong state
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to load
wait_for_weasis 60
sleep 4

# Dismiss first-run dialog if it appears
dismiss_first_run_dialog
sleep 2

# Maximize Window for visibility
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Allow UI to stabilize and take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

# Final check that screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured successfully."
fi

echo "=== Setup complete ==="