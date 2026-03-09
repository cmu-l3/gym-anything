#!/bin/bash
echo "=== Setting up Mediastinal Anatomy Annotation Task ==="

# Source common utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Python dependencies
pip3 install -q numpy nibabel pydicom 2>/dev/null || true

# ============================================================
# Set up directories
# ============================================================
LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean up any previous task artifacts
rm -f "$LIDC_DIR/mediastinal_landmarks.mrk.json" 2>/dev/null || true
rm -f /tmp/mediastinal_task_result.json 2>/dev/null || true

# Record initial state - no landmarks should exist
echo "0" > /tmp/initial_landmark_count.txt

# ============================================================
# Prepare chest CT data
# ============================================================
echo "Preparing chest CT data..."

# Try to run LIDC preparation script
export PATIENT_ID
export LIDC_DIR
export GROUND_TRUTH_DIR

if [ -f /workspace/scripts/prepare_lidc_data.sh ]; then
    /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" 2>/dev/null || true
fi

# Check if we have data, otherwise create synthetic
CT_FILE=""
if [ -d "$LIDC_DIR/$PATIENT_ID/DICOM" ] && [ "$(ls -1 "$LIDC_DIR/$PATIENT_ID/DICOM/" 2>/dev/null | wc -l)" -gt 10 ]; then
    CT_FILE="$LIDC_DIR/$PATIENT_ID/DICOM"
    echo "Using DICOM data from: $CT_FILE"
elif [ -f "$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz" ]; then
    CT_FILE="$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz"
    echo "Using NIfTI data from: $CT_FILE"
else
    echo "Creating synthetic chest CT with mediastinal structures..."
    
    mkdir -p "$LIDC_DIR/$PATIENT_ID"
    
    python3 << 'PYEOF'
import numpy as np
import os
import json

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

lidc_dir = "/home/ga/Documents/SlicerData/LIDC"
gt_dir = "/var/lib/slicer/ground_truth"
patient_id = "LIDC-IDRI-0001"

os.makedirs(f"{lidc_dir}/{patient_id}", exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

np.random.seed(42)

# Create chest CT volume: 256 x 256 x 100 slices
nx, ny, nz = 256, 256, 100
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Create affine matrix (RAS orientation)
affine = np.eye(4)
affine[0, 0] = -spacing[0]  # R->L
affine[1, 1] = -spacing[1]  # A->P
affine[2, 2] = spacing[2]   # S
# Set origin so center is approximately at 0,0,0
affine[0, 3] = nx * spacing[0] / 2
affine[1, 3] = ny * spacing[1] / 2
affine[2, 3] = -nz * spacing[2] / 2

# Initialize with air (-1000 HU)
ct_data = np.full((nx, ny, nz), -1000, dtype=np.int16)

# Body outline (elliptical thorax)
Y, X = np.ogrid[:nx, :ny]
cx, cy = nx // 2, ny // 2

# Create body contour
body_a, body_b = 100, 80
body_mask = ((X - cx)**2 / body_a**2 + (Y - cy)**2 / body_b**2) <= 1.0

# Fill body with soft tissue
for z in range(nz):
    ct_data[:, :, z][body_mask] = np.random.normal(40, 10, np.sum(body_mask)).astype(np.int16)

# Create lungs (bilateral, air-filled)
lung_offset = 40
lung_a, lung_b = 45, 55
for side in [-1, 1]:
    lung_cx = cx + side * lung_offset
    lung_mask = ((X - lung_cx)**2 / lung_a**2 + (Y - cy)**2 / lung_b**2) <= 1.0
    for z in range(10, 90):
        ct_data[:, :, z][lung_mask & body_mask] = np.random.normal(-850, 30, 
            np.sum(lung_mask & body_mask)).astype(np.int16)

# Create spine (posterior, high density)
spine_cx, spine_cy = cx, cy + 70
spine_r = 15
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= spine_r**2
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 50, np.sum(spine_mask)).astype(np.int16)

# Ground truth landmark positions (in RAS coordinates)
gt_landmarks = {}

# Ascending Aorta (anterior, right of midline in image coords -> left in RAS)
asc_aorta_cx, asc_aorta_cy = cx - 15, cy + 10
asc_aorta_r = 12
asc_aorta_z = 45
for z in range(30, 60):
    aorta_mask = ((X - asc_aorta_cx)**2 + (Y - asc_aorta_cy)**2) <= asc_aorta_r**2
    ct_data[:, :, z][aorta_mask] = np.random.normal(55, 15, np.sum(aorta_mask)).astype(np.int16)

# Convert voxel to RAS coordinates
def voxel_to_ras(vx, vy, vz):
    voxel_coord = np.array([vx, vy, vz, 1])
    ras_coord = affine @ voxel_coord
    return [float(ras_coord[0]), float(ras_coord[1]), float(ras_coord[2])]

gt_landmarks['AscendingAorta'] = {
    'voxel': [int(asc_aorta_cx), int(asc_aorta_cy), int(asc_aorta_z)],
    'ras': voxel_to_ras(asc_aorta_cx, asc_aorta_cy, asc_aorta_z),
    'expected_hu_range': [-100, 200]
}

# Descending Aorta (posterior, left of spine)
desc_aorta_cx, desc_aorta_cy = cx + 5, cy + 55
desc_aorta_r = 10
desc_aorta_z = 55
for z in range(20, 90):
    aorta_mask = ((X - desc_aorta_cx)**2 + (Y - desc_aorta_cy)**2) <= desc_aorta_r**2
    ct_data[:, :, z][aorta_mask] = np.random.normal(50, 15, np.sum(aorta_mask)).astype(np.int16)

gt_landmarks['DescendingAorta'] = {
    'voxel': [int(desc_aorta_cx), int(desc_aorta_cy), int(desc_aorta_z)],
    'ras': voxel_to_ras(desc_aorta_cx, desc_aorta_cy, desc_aorta_z),
    'expected_hu_range': [-100, 200]
}

# Pulmonary Artery (anterior to ascending aorta)
pa_cx, pa_cy = cx - 25, cy - 5
pa_r = 10
pa_z = 42
for z in range(35, 50):
    pa_mask = ((X - pa_cx)**2 + (Y - pa_cy)**2) <= pa_r**2
    ct_data[:, :, z][pa_mask] = np.random.normal(45, 15, np.sum(pa_mask)).astype(np.int16)

gt_landmarks['PulmonaryArtery'] = {
    'voxel': [int(pa_cx), int(pa_cy), int(pa_z)],
    'ras': voxel_to_ras(pa_cx, pa_cy, pa_z),
    'expected_hu_range': [-100, 200]
}

# Trachea (central, air-filled)
trachea_cx, trachea_cy = cx, cy + 25
trachea_r = 8
trachea_z = 70
for z in range(50, 95):
    trachea_mask = ((X - trachea_cx)**2 + (Y - trachea_cy)**2) <= trachea_r**2
    ct_data[:, :, z][trachea_mask] = np.random.normal(-950, 20, np.sum(trachea_mask)).astype(np.int16)

gt_landmarks['Trachea'] = {
    'voxel': [int(trachea_cx), int(trachea_cy), int(trachea_z)],
    'ras': voxel_to_ras(trachea_cx, trachea_cy, trachea_z),
    'expected_hu_range': [-1024, -700]
}

# Left Atrium (posterior cardiac chamber)
la_cx, la_cy = cx + 10, cy + 30
la_a, la_b = 25, 20
la_z = 35
for z in range(25, 45):
    la_mask = ((X - la_cx)**2 / la_a**2 + (Y - la_cy)**2 / la_b**2) <= 1.0
    ct_data[:, :, z][la_mask] = np.random.normal(50, 15, np.sum(la_mask)).astype(np.int16)

gt_landmarks['LeftAtrium'] = {
    'voxel': [int(la_cx), int(la_cy), int(la_z)],
    'ras': voxel_to_ras(la_cx, la_cy, la_z),
    'expected_hu_range': [-100, 200]
}

# Esophagus (posterior to trachea)
esoph_cx, esoph_cy = cx, cy + 40
esoph_r = 5
esoph_z = 65
for z in range(40, 90):
    esoph_mask = ((X - esoph_cx)**2 + (Y - esoph_cy)**2) <= esoph_r**2
    ct_data[:, :, z][esoph_mask] = np.random.normal(35, 20, np.sum(esoph_mask)).astype(np.int16)

gt_landmarks['Esophagus'] = {
    'voxel': [int(esoph_cx), int(esoph_cy), int(esoph_z)],
    'ras': voxel_to_ras(esoph_cx, esoph_cy, esoph_z),
    'expected_hu_range': [-150, 150]
}

# Save CT volume
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = f"{lidc_dir}/{patient_id}/chest_ct.nii.gz"
nib.save(ct_nii, ct_path)
print(f"Created synthetic chest CT: {ct_path}")
print(f"  Shape: {ct_data.shape}, Spacing: {spacing}")

# Save ground truth landmarks
gt_path = f"{gt_dir}/{patient_id}_mediastinal_gt.json"
gt_data = {
    'patient_id': patient_id,
    'spacing_mm': list(spacing),
    'shape': list(ct_data.shape),
    'affine': affine.tolist(),
    'landmarks': gt_landmarks,
    'spatial_relationships': {
        'ascending_anterior_to_descending': True,
        'pulmonary_anterior_to_ascending': True,
        'trachea_anterior_to_esophagus': True
    }
}
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Saved ground truth: {gt_path}")

# Save patient ID for later scripts
with open('/tmp/lidc_patient_id', 'w') as f:
    f.write(patient_id)
PYEOF

    CT_FILE="$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz"
fi

# Store patient ID for verification
echo "$PATIENT_ID" > /tmp/lidc_patient_id

# Verify CT exists
if [ ! -f "$CT_FILE" ] && [ ! -d "$CT_FILE" ]; then
    echo "ERROR: No CT data available at $CT_FILE"
    exit 1
fi

echo "CT data ready: $CT_FILE"

# ============================================================
# Start 3D Slicer with the chest CT
# ============================================================
echo "Starting 3D Slicer..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT file
if [ -f "$CT_FILE" ]; then
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_task.log 2>&1 &
else
    # DICOM directory - start Slicer without file
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_task.log 2>&1 &
fi

SLICER_PID=$!
echo "Slicer PID: $SLICER_PID"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for full load
sleep 15

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Re-maximize after dialogs
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Mediastinal Anatomy Annotation"
echo "====================================="
echo ""
echo "Identify and annotate six mediastinal structures:"
echo "  1. AscendingAorta - anterior great vessel"
echo "  2. DescendingAorta - posterior vessel along spine"
echo "  3. PulmonaryArtery - anterior to ascending aorta"
echo "  4. Trachea - air-filled central airway (appears dark)"
echo "  5. LeftAtrium - posterior heart chamber"
echo "  6. Esophagus - posterior to trachea"
echo ""
echo "Use the Markups module to place fiducial points."
echo "Name each fiducial EXACTLY as specified above."
echo ""
echo "Save landmarks to: ~/Documents/SlicerData/LIDC/mediastinal_landmarks.mrk.json"
echo ""