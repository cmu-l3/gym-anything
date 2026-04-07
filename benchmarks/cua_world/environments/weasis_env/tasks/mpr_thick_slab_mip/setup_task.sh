#!/bin/bash
echo "=== Setting up MPR Thick Slab task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Clean up any pre-existing files that might interfere with verification
rm -f "$EXPORT_DIR/mip_slab_view.png"
rm -f "$EXPORT_DIR/mpr_settings.txt"

# Ensure we have a volumetric CT series (at least 15 slices for MPR to be meaningful)
CT_DIR="/home/ga/DICOM/samples/ct_scan"
FILE_COUNT=$(ls -1 "$CT_DIR"/*.dcm "$CT_DIR"/*.DCM 2>/dev/null | wc -l || echo "0")

if [ "$FILE_COUNT" -lt 10 ]; then
    echo "Sufficient CT slices not found in default dir. Generating synthetic 3D series..."
    CT_DIR="/home/ga/DICOM/samples/synthetic_volumetric"
    mkdir -p "$CT_DIR"
    
    python3 << 'PYEOF'
import os
import numpy as np

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_volumetric_dicom_series(out_dir, num_slices=30, size=256):
        study_uid = generate_uid()
        series_uid = generate_uid()
        
        for z in range(num_slices):
            filename = os.path.join(out_dir, f"CT_slice_{z+1:03d}.dcm")
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
            ds.PatientName = "Volumetric^MPR^Test"
            ds.PatientID = "MPR001"
            ds.StudyDescription = "MPR Volumetric Test Study"
            ds.SeriesDescription = "Axial CT Series"
            
            # MPR critical metadata
            ds.InstanceNumber = z + 1
            ds.SliceThickness = 1.0
            ds.PixelSpacing = [1.0, 1.0]
            ds.ImagePositionPatient = [0.0, 0.0, float(z)]
            ds.ImageOrientationPatient = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]

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

            # Create a 3D tubular structure (like a vessel) that weaves through slices
            image = np.zeros((size, size), dtype=np.uint16)
            image[:, :] = 0  # air/background
            
            # Center of the "vessel" moves slightly with z to create a 3D effect
            center_x = size // 2 + int(30 * np.sin(z / 5.0))
            center_y = size // 2 + int(30 * np.cos(z / 5.0))
            radius = 15
            
            for i in range(size):
                for j in range(size):
                    if (i - center_y)**2 + (j - center_x)**2 < radius**2:
                        image[i, j] = 2000  # High intensity contrast (MIP target)
                        
            ds.PixelData = image.tobytes()
            ds.save_as(filename)
        print(f"Created {num_slices} volumetric slices in {out_dir}")

    create_volumetric_dicom_series(os.path.expanduser("~/DICOM/samples/synthetic_volumetric"))
except Exception as e:
    print(f"Error generating DICOMs: {e}")
PYEOF
    chown -R ga:ga "$CT_DIR"
fi

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis, opening the entire directory to load it as a series
echo "Launching Weasis with CT directory..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$CT_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$CT_DIR' > /tmp/weasis_ga.log 2>&1 &"
sleep 10

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog
sleep 1

# Maximize Weasis Window
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Let the UI settle and series load completely
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="