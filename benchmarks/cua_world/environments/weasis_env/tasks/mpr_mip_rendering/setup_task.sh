#!/bin/bash
echo "=== Setting up mpr_mip_rendering task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create export directory and clean any previous files
EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/mip_projection.png" 2>/dev/null || true
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Generate a synthetic multi-slice CT specifically designed to test MIP
# It contains a diagonal high-density "vessel" that appears as a small dot in a thin slice,
# but as a long thick line in a >15mm MIP projection.
SAMPLE_DIR="/home/ga/DICOM/samples/vascular_ct"
echo "Creating synthetic multi-slice CT volume..."
mkdir -p "$SAMPLE_DIR"

python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    size = 256
    num_slices = 30
    study_uid = generate_uid()
    series_uid = generate_uid()
    
    # We create a volume with a diagonal vessel.
    # In any orthogonal plane (Axial, Coronal, Sagittal), a 1mm slice intersects the 
    # vessel at a single point (small dot). A 15mm MIP captures a long segment of it.
    
    for z in range(num_slices):
        filename = f"/home/ga/DICOM/samples/vascular_ct/slice_{z:03d}.dcm"
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
        
        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "MIP^Vascular"
        ds.PatientID = "MIP002"
        ds.StudyDescription = "MPR MIP Evaluation"
        ds.SeriesDescription = "Axial 1mm"
        
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
        ds.SliceThickness = 1.0
        ds.ImagePositionPatient = [0.0, 0.0, float(z)]
        
        img = np.zeros((size, size), dtype=np.uint16)
        
        # Soft tissue background (cylinder)
        cy, cx = size//2, size//2
        radius = size//3
        y, x = np.ogrid[:size, :size]
        mask = (x - cx)**2 + (y - cy)**2 <= radius**2
        img[mask] = 1040  # Soft tissue (~40 HU)
        
        # Diagonal contrast-filled vessel
        # Moves from top-left to bottom-right across the slices
        vx = int(size * 0.3 + (size * 0.4 * z / num_slices))
        vy = int(size * 0.3 + (size * 0.4 * z / num_slices))
        vmask = (x - vx)**2 + (y - vy)**2 <= (size//15)**2
        img[vmask] = 2000  # High density vessel
        
        ds.PixelData = img.tobytes()
        ds.save_as(filename)
    print(f"Created {num_slices} slices in {SAMPLE_DIR}")
except Exception as e:
    print(f"Error generating DICOMs: {e}")
PYEOF

chown -R ga:ga "$SAMPLE_DIR"

# Ensure Weasis is closed before starting
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the directory (loads the entire series automatically)
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$SAMPLE_DIR' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application to be ready
wait_for_weasis 60
sleep 5

# Dismiss first-run dialog
dismiss_first_run_dialog
sleep 2

# Maximize Weasis Window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot showing loaded 2D series
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "The 3D vascular CT series is loaded in the 2D viewer."
echo "Agent must open MPR, switch to MIP, increase thickness to >=15mm, and export."