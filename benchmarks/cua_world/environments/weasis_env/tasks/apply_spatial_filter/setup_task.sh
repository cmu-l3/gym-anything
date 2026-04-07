#!/bin/bash
echo "=== Setting up apply_spatial_filter task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create export dir and clean any stale files
mkdir -p /home/ga/DICOM/exports
rm -f /home/ga/DICOM/exports/sharpened_ct.tiff 2>/dev/null || true
rm -f /home/ga/DICOM/exports/filter_applied.txt 2>/dev/null || true
chown -R ga:ga /home/ga/DICOM/exports

# Find an authentic CT DICOM sample
SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR/ct_scan" "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | grep -i "ct" | head -1)

if [ -z "$DICOM_FILE" ] || [ ! -f "$DICOM_FILE" ]; then
    DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)
fi

# Fallback: Generate synthetic DICOM with high-frequency edges specifically designed for testing spatial filters
if [ -z "$DICOM_FILE" ] || [ ! -f "$DICOM_FILE" ]; then
    echo "Creating synthetic DICOM file for testing..."
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
        ds.PatientName = "Spatial^Filter"
        ds.PatientID = "FILT001"
        ds.StudyDescription = "Filter Test Study"
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
        image[:, :] = 124
        center = size // 2
        
        # Hard edges perfect for edge-enhancement filter detection
        image[center-50:center+50, center-50:center+50] = 2000
        image[center-100:center-60, center+60:center+100] = 3000
        
        # Add normal noise
        noise = np.random.normal(0, 50, (size, size)).astype(np.int16)
        image = np.clip(image.astype(np.int32) + noise, 0, 4095).astype(np.uint16)

        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")

    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "filter_test_ct.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/filter_test_ct.dcm"
fi

echo "Using DICOM file: $DICOM_FILE"

# Create unsharpened baseline reference for programmatic verification
mkdir -p /var/lib/weasis_ground_truth
python3 << PYEOF
import os
import json
import numpy as np
import cv2
try:
    import pydicom
    from PIL import Image

    dicom_path = "$DICOM_FILE"
    ds = pydicom.dcmread(dicom_path)
    pixel_array = ds.pixel_array

    # Use native DICOM Window Level settings to mimic standard display view
    wc = float(ds.WindowCenter) if hasattr(ds, 'WindowCenter') else float(np.median(pixel_array))
    ww = float(ds.WindowWidth) if hasattr(ds, 'WindowWidth') else float(np.ptp(pixel_array))

    if isinstance(wc, (list, tuple, pydicom.multival.MultiValue)): wc = float(wc[0])
    if isinstance(ww, (list, tuple, pydicom.multival.MultiValue)): ww = float(ww[0])

    vmin = wc - ww / 2
    vmax = wc + ww / 2
    img_norm = np.clip((pixel_array - vmin) / (vmax - vmin) * 255.0, 0, 255).astype(np.uint8)

    # Calculate baseline Laplacian variance (measure of edge definition / sharpness)
    laplacian_var = cv2.Laplacian(img_norm, cv2.CV_64F).var()

    Image.fromarray(img_norm).save('/var/lib/weasis_ground_truth/baseline_ct.tiff')
    with open('/var/lib/weasis_ground_truth/baseline_stats.json', 'w') as f:
        json.dump({'laplacian_var': float(laplacian_var), 'wc': float(wc), 'ww': float(ww)}, f)
    print(f"Baseline Laplacian variance: {laplacian_var}")
except Exception as e:
    print(f"Error creating baseline: {e}")
    with open('/var/lib/weasis_ground_truth/baseline_stats.json', 'w') as f:
        json.dump({'laplacian_var': 0, 'error': str(e)}, f)
PYEOF
chmod -R 755 /var/lib/weasis_ground_truth

# Start Weasis with the target DICOM image
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

# Take initial proof screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="