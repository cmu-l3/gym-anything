#!/bin/bash
echo "=== Setting up correlate_optical_photo_dicom task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Export Directory
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"
# Clean up any previous runs
rm -f "$EXPORT_DIR/multimodal_comparison.png" 2>/dev/null || true

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Create the "Clinical Photo" on the Desktop
PHOTO_PATH="/home/ga/Desktop/clinical_photo.jpg"
echo "Generating synthetic clinical photo..."
python3 << 'PYEOF'
import numpy as np
try:
    from PIL import Image
    # Create a 512x512 image simulating reddish tissue (endoscopy/clinical photo)
    img = np.zeros((512, 512, 3), dtype=np.uint8)
    img[:, :, 0] = 180  # R
    img[:, :, 1] = 90   # G
    img[:, :, 2] = 90   # B
    
    # Add some noise and a distinct "tumor" or "lesion" blob in the center
    noise = np.random.randint(0, 40, (512, 512, 3), dtype=np.int16)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    
    # Draw a distinct dark spot in the middle
    center = 256
    radius = 50
    for i in range(512):
        for j in range(512):
            if (i - center)**2 + (j - center)**2 < radius**2:
                img[i, j, :] = [100, 40, 40]
                
    Image.fromarray(img).save("/home/ga/Desktop/clinical_photo.jpg", quality=90)
    print("Clinical photo created at ~/Desktop/clinical_photo.jpg")
except Exception as e:
    print(f"Error creating photo: {e}")
PYEOF
chown ga:ga "$PHOTO_PATH"

# 4. Ensure a DICOM sample exists
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
        ds.PatientName = "Correlation^Test"
        ds.PatientID = "CORR001"
        ds.StudyDescription = "Multimodal Correlation Study"
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
        center = size // 2
        for i in range(size):
            for j in range(size):
                if (i - center)**2 + (j - center)**2 < (size*0.3)**2:
                    image[i, j] = 2000
        ds.PixelData = image.tobytes()
        ds.save_as(filename)

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "ct_scan.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/ct_scan.dcm"
fi

# 5. Launch Weasis with the DICOM file pre-loaded
pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60
sleep 2
dismiss_first_run_dialog
sleep 2

# Maximize Weasis for clarity
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="