#!/bin/bash
echo "=== Setting up recist_tumor_measurement task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Clean previous artifacts
rm -f "$EXPORT_DIR/recist_annotation.png" 2>/dev/null || true
rm -f "$EXPORT_DIR/recist_report.txt" 2>/dev/null || true

# Find a CT DICOM
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) | grep -i "ct" | head -1)

if [ -z "$DICOM_FILE" ]; then
    DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) | head -1)
fi

# Fallback synthetic generation if absolutely nothing exists
if [ -z "$DICOM_FILE" ]; then
    echo "Creating synthetic DICOM file for RECIST..."
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_recist_dicom(filename, size=512):
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
        ds.PatientName = "RECIST^Test"
        ds.PatientID = "REC001"
        ds.StudyDescription = "Oncology Evaluation"
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
        
        # Create image with a distinct "tumor" structure
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 500  # background
        
        # Draw a central elliptical tumor
        cy, cx = size//2, size//2
        a, b = 60, 40 # semi-major, semi-minor
        for y in range(size):
            for x in range(size):
                if ((x-cx)**2)/(a**2) + ((y-cy)**2)/(b**2) <= 1:
                    image[y, x] = 1040 + np.random.randint(-20, 20)
                    
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        
    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_recist_dicom(os.path.join(sample_dir, "recist_phantom.dcm"))
except Exception as e:
    print(f"Error creating synthetic DICOM: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/recist_phantom.dcm"
fi

# Launch weasis
pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis with $DICOM_FILE..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60
sleep 2

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

dismiss_first_run_dialog
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="