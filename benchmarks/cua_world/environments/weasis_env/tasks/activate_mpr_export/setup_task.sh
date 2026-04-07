#!/bin/bash
set -euo pipefail
echo "=== Setting up activate_mpr_export task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
VOLUME_DIR="/home/ga/DICOM/samples/mpr_volume"

# Prepare clean export directory
rm -rf "$EXPORT_DIR"/* 2>/dev/null || true
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Generate realistic 60-slice CT volume configured for 3D reconstruction
echo "Generating 60-slice volumetric CT series for MPR..."
mkdir -p "$VOLUME_DIR"
python3 << 'PYEOF'
import os
import numpy as np
import datetime

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    
    def create_series(base_dir, num_slices=60, size=256):
        study_uid = generate_uid()
        series_uid = generate_uid()
        
        dt = datetime.datetime.now()
        date_str = dt.strftime('%Y%m%d')
        time_str = dt.strftime('%H%M%S.%f')
        
        for i in range(num_slices):
            filename = os.path.join(base_dir, f"slice_{i:03d}.dcm")
            
            file_meta = Dataset()
            file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2' # CT
            file_meta.MediaStorageSOPInstanceUID = generate_uid()
            file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
            
            ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
            
            # Linking metadata required for a cohesive volume
            ds.ContentDate = date_str
            ds.ContentTime = time_str
            ds.StudyInstanceUID = study_uid
            ds.SeriesInstanceUID = series_uid
            ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
            ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
            ds.Modality = "CT"
            ds.PatientName = "MPR^Patient"
            ds.PatientID = "MPR001"
            ds.StudyDescription = "Abdomen CT"
            ds.SeriesDescription = "Axial Volume for MPR"
            
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
            
            # Spatial metadata critical for MPR to function
            ds.PixelSpacing = [0.9, 0.9]
            ds.SliceThickness = 2.5
            ds.SpacingBetweenSlices = 2.5
            z_pos = -150.0 + i * 2.5
            ds.ImagePositionPatient = [-100.0, -100.0, float(z_pos)]
            ds.ImageOrientationPatient = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
            ds.InstanceNumber = i + 1
            ds.SliceLocation = float(z_pos)
            
            # Create synthetic anatomical structures (varying across Z axis)
            image = np.zeros((size, size), dtype=np.int16)
            image[:, :] = 24  # Background
            
            center = size // 2
            for y in range(size):
                for x in range(size):
                    # Base body contour
                    if ((x - center)**2) / (100**2) + ((y - center)**2) / (80**2) < 1:
                        image[y, x] = 1064
                        
                    # Internal 3D structures (kidney/mass simulation)
                    z_dist = abs(i - 30)
                    if z_dist < 15:
                        if (x - (center - 40))**2 + (y - center)**2 + (z_dist * 3)**2 < 30**2:
                            image[y, x] = 1124
                        if (x - (center + 40))**2 + (y - center)**2 + (z_dist * 3)**2 < 30**2:
                            image[y, x] = 1124
                            
            ds.PixelData = image.tobytes()
            ds.save_as(filename)

    create_series("/home/ga/DICOM/samples/mpr_volume")
    print("Volume generation complete.")
except Exception as e:
    print(f"Error generating volume: {e}")
PYEOF

chown -R ga:ga "$VOLUME_DIR"

# Ensure Weasis is stopped before launching new instance
pkill -f weasis >/dev/null 2>&1 || true
sleep 2

# Launch Weasis loading the entire 60-slice directory as a single volume
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$VOLUME_DIR' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$VOLUME_DIR' > /tmp/weasis_ga.log 2>&1 &"

# Wait for application and handle heavy loading 
wait_for_weasis 60
sleep 10

# Maximize Weasis Window
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Dismiss welcome tips
sleep 2
dismiss_first_run_dialog

# Ensure still maximized
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

sleep 2

# Take initial screenshot showing axial series
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="