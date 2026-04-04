#!/bin/bash
echo "=== Setting up MinIP Airway Visualization Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare LIDC data
echo "Preparing LIDC-IDRI chest CT data..."
export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || true

# If LIDC download failed, generate synthetic chest CT with airways
if [ ! -d "$LIDC_DIR/$PATIENT_ID/DICOM" ] || [ "$(find "$LIDC_DIR/$PATIENT_ID/DICOM" -type f 2>/dev/null | wc -l)" -lt 10 ]; then
    echo "LIDC download incomplete, generating synthetic chest CT with airways..."
    
    python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

np.random.seed(42)

# Create chest CT with realistic airways
# Shape: 512 x 512 x 300 (typical chest CT dimensions)
nx, ny, nz = 256, 256, 200
spacing = (0.7, 0.7, 1.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize CT volume with air (-1000 HU)
ct_data = np.ones((nx, ny, nz), dtype=np.int16) * -1000

# Create body outline (elliptical thorax)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Thorax cross-section (elliptical)
thorax_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (70**2)) <= 1.0

# Fill thorax with soft tissue (~40 HU with noise)
for z in range(nz):
    ct_data[:, :, z][thorax_mask] = np.random.normal(40, 20, (np.sum(thorax_mask),)).astype(np.int16)

# Create spine (posterior, high density)
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 60, (np.sum(spine_mask),)).astype(np.int16)

# Create lung fields (air-filled, -800 to -900 HU)
# Right lung (patient's right = image left)
right_lung_cx, right_lung_cy = center_x - 35, center_y - 10
left_lung_cx, left_lung_cy = center_x + 35, center_y - 10

for z in range(30, nz - 30):
    # Adjust lung size based on z position (smaller at apex/base)
    z_factor = 1.0 - 0.5 * ((z - nz/2) / (nz/2))**2
    lung_r = int(45 * z_factor)
    
    # Right lung
    right_mask = ((X - right_lung_cx)**2 / (lung_r**2) + (Y - right_lung_cy)**2 / ((lung_r*0.8)**2)) <= 1.0
    ct_data[:, :, z][right_mask & thorax_mask] = np.random.normal(-850, 50, (np.sum(right_mask & thorax_mask),)).astype(np.int16)
    
    # Left lung
    left_mask = ((X - left_lung_cx)**2 / (lung_r**2) + (Y - left_lung_cy)**2 / ((lung_r*0.8)**2)) <= 1.0
    ct_data[:, :, z][left_mask & thorax_mask] = np.random.normal(-850, 50, (np.sum(left_mask & thorax_mask),)).astype(np.int16)

# ============================================================
# Create airway tree (CRITICAL for this task)
# ============================================================
# Airways are air-filled tubes (-1000 HU)
# Trachea: runs from top (~z=180) to carina (~z=120)
# Carina: bifurcation point
# Main bronchi: diverge from carina
# Lobar bronchi: branch from main bronchi

# Ground truth measurements
trachea_diameter_mm = 20.0  # Normal adult trachea
right_bronchus_diameter_mm = 14.0  # Typically larger
left_bronchus_diameter_mm = 12.0  # Typically smaller

# Convert to voxels
trachea_radius_vox = (trachea_diameter_mm / 2.0) / spacing[0]
right_radius_vox = (right_bronchus_diameter_mm / 2.0) / spacing[0]
left_radius_vox = (left_bronchus_diameter_mm / 2.0) / spacing[0]

# Trachea position (midline, anterior to spine)
trachea_cx, trachea_cy = center_x, center_y + 25
carina_z = 120  # Slice where carina is located

# Create trachea (from top to carina)
print(f"Creating trachea: diameter={trachea_diameter_mm}mm, center=({trachea_cx}, {trachea_cy})")
for z in range(carina_z, nz - 10):
    # Slight variation in position
    offset = 2 * np.sin(z * 0.05)
    trachea_mask = ((X - (trachea_cx + offset))**2 + (Y - trachea_cy)**2) <= trachea_radius_vox**2
    ct_data[:, :, z][trachea_mask] = -1000  # Air

# Create right main bronchus (angles down and to the right)
print(f"Creating right main bronchus: diameter={right_bronchus_diameter_mm}mm")
for i, z in enumerate(range(carina_z, carina_z - 40, -1)):
    # Move laterally as we go down
    lateral_offset = i * 0.8
    rb_cx = trachea_cx - lateral_offset
    rb_cy = trachea_cy - i * 0.2
    rb_mask = ((X - rb_cx)**2 + (Y - rb_cy)**2) <= right_radius_vox**2
    ct_data[:, :, z][rb_mask] = -1000

# Create left main bronchus (angles down and to the left, more horizontal)
print(f"Creating left main bronchus: diameter={left_bronchus_diameter_mm}mm")
for i, z in enumerate(range(carina_z, carina_z - 45, -1)):
    lateral_offset = i * 0.6
    lb_cx = trachea_cx + lateral_offset
    lb_cy = trachea_cy - i * 0.15
    lb_mask = ((X - lb_cx)**2 + (Y - lb_cy)**2) <= left_radius_vox**2
    ct_data[:, :, z][lb_mask] = -1000

# Create lobar bronchi branches
# Right upper lobe bronchus (branches early)
rul_branch_z = carina_z - 15
for i, z in enumerate(range(rul_branch_z, rul_branch_z - 20, -1)):
    rul_cx = trachea_cx - 20 - i * 0.5
    rul_cy = trachea_cy - 20 - i * 0.3
    rul_radius = right_radius_vox * 0.6
    rul_mask = ((X - rul_cx)**2 + (Y - rul_cy)**2) <= rul_radius**2
    ct_data[:, :, z][rul_mask] = -1000

# Left upper lobe bronchus
lul_branch_z = carina_z - 20
for i, z in enumerate(range(lul_branch_z, lul_branch_z - 20, -1)):
    lul_cx = trachea_cx + 25 + i * 0.4
    lul_cy = trachea_cy - 15 - i * 0.3
    lul_radius = left_radius_vox * 0.6
    lul_mask = ((X - lul_cx)**2 + (Y - lul_cy)**2) <= lul_radius**2
    ct_data[:, :, z][lul_mask] = -1000

# ============================================================
# Save NIfTI volume
# ============================================================
patient_dir = os.path.join(lidc_dir, patient_id)
os.makedirs(patient_dir, exist_ok=True)

ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(patient_dir, "chest_ct.nii.gz")
nib.save(ct_img, ct_path)
print(f"Chest CT saved: {ct_path} (shape: {ct_data.shape})")

# ============================================================
# Save ground truth
# ============================================================
# Calculate carina position in mm
carina_position_mm = [
    float(trachea_cx * spacing[0]),
    float(trachea_cy * spacing[1]),
    float(carina_z * spacing[2])
]

# Measurement locations (2cm above carina for trachea)
trachea_measurement_z = carina_z + int(20.0 / spacing[2])  # 2cm above carina

ground_truth = {
    "patient_id": patient_id,
    "volume_shape": list(ct_data.shape),
    "voxel_spacing_mm": list(spacing),
    "carina_position_mm": carina_position_mm,
    "carina_slice_index": carina_z,
    "trachea_measurement_slice": trachea_measurement_z,
    "measurements": {
        "trachea_diameter_mm": trachea_diameter_mm,
        "right_main_bronchus_diameter_mm": right_bronchus_diameter_mm,
        "left_main_bronchus_diameter_mm": left_bronchus_diameter_mm
    },
    "landmarks": {
        "trachea_center_mm": [trachea_cx * spacing[0], trachea_cy * spacing[1], (carina_z + 30) * spacing[2]],
        "carina_mm": carina_position_mm,
        "right_main_bronchus_mm": [(trachea_cx - 15) * spacing[0], (trachea_cy - 5) * spacing[1], (carina_z - 20) * spacing[2]],
        "left_main_bronchus_mm": [(trachea_cx + 15) * spacing[0], (trachea_cy - 3) * spacing[1], (carina_z - 25) * spacing[2]]
    },
    "normal_ranges": {
        "trachea_mm": [15, 25],
        "right_bronchus_mm": [10, 16],
        "left_bronchus_mm": [9, 14]
    }
}

gt_path = os.path.join(gt_dir, f"{patient_id}_airway_gt.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)
print(f"Ground truth saved: {gt_path}")

print("\nSynthetic chest CT with airways created successfully")
print(f"Trachea diameter: {trachea_diameter_mm}mm")
print(f"Right main bronchus: {right_bronchus_diameter_mm}mm")
print(f"Left main bronchus: {left_bronchus_diameter_mm}mm")
PYEOF

    PATIENT_ID="LIDC-IDRI-0001"
fi

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi
echo "$PATIENT_ID" > /tmp/lidc_patient_id

# Find the CT volume
CT_FILE=""
if [ -f "$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz" ]; then
    CT_FILE="$LIDC_DIR/$PATIENT_ID/chest_ct.nii.gz"
elif [ -d "$LIDC_DIR/$PATIENT_ID/DICOM" ]; then
    CT_FILE="$LIDC_DIR/$PATIENT_ID/DICOM"
fi

echo "Using patient: $PATIENT_ID"
echo "CT data: $CT_FILE"

# Clear any previous outputs
rm -f "$LIDC_DIR/minip_airway_visualization.png" 2>/dev/null || true
rm -f "$LIDC_DIR/airway_landmarks.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/airway_measurements.json" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "screenshot_exists": false,
    "landmarks_exists": false,
    "measurements_exists": false,
    "task_start_time": $(date +%s),
    "patient_id": "$PATIENT_ID"
}
EOF

# Create Slicer Python script to load the chest CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

patient_id = "$PATIENT_ID"
lidc_dir = "$LIDC_DIR"

# Try NIfTI file first
nifti_path = os.path.join(lidc_dir, patient_id, "chest_ct.nii.gz")
dicom_dir = os.path.join(lidc_dir, patient_id, "DICOM")

volume_node = None

if os.path.exists(nifti_path):
    print(f"Loading NIfTI volume: {nifti_path}")
    volume_node = slicer.util.loadVolume(nifti_path)
elif os.path.isdir(dicom_dir):
    print(f"Loading DICOM series from: {dicom_dir}")
    from DICOMLib import DICOMUtils
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            studies = db.studiesForPatient(patientUIDs[0])
            if studies:
                series = db.seriesForStudy(studies[0])
                if series:
                    volume_node = DICOMUtils.loadSeriesByUID([series[0]])
                    if isinstance(volume_node, list):
                        volume_node = volume_node[0] if volume_node else None

if volume_node:
    volume_node.SetName("ChestCT")
    print(f"Volume loaded: {volume_node.GetName()}")
    print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
    
    # Set lung window/level for airway visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Lung window: W=1500, L=-500 (good for airways)
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-500)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Center on the data
    slicer.util.resetSliceViews()
    
    # Set to approximately carina level
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2 + 20  # Slightly above center for airways
    
    sliceWidget = slicer.app.layoutManager().sliceWidget("Red")
    sliceWidget.sliceLogic().GetSliceNode().SetSliceOffset(center_z)
    
    print(f"Setup complete - ready for MinIP airway visualization task")
    print(f"Current window/level: W=1500, L=-500 (lung window)")
else:
    print("ERROR: Could not load chest CT volume")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
fi

sleep 3

# Take initial screenshot
take_screenshot /tmp/minip_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Minimum Intensity Projection (MinIP) Airway Visualization"
echo "================================================================"
echo ""
echo "Create a MinIP visualization of the central airways and measure airway diameters."
echo ""
echo "Instructions:"
echo "  1. Create a MinIP slab (20-30mm thick) in the coronal plane"
echo "     - MinIP shows MINIMUM values (air appears dark)"
echo "     - Use Volume Rendering module or Slab Reconstruction"
echo ""
echo "  2. Annotate these structures with fiducial markers:"
echo "     - Trachea, Carina, Right main bronchus, Left main bronchus"
echo ""
echo "  3. Measure diameters at:"
echo "     - Trachea (2cm above carina): normal 15-25mm"
echo "     - Right main bronchus: normal 10-16mm"
echo "     - Left main bronchus: normal 9-14mm"
echo ""
echo "  4. Save outputs to ~/Documents/SlicerData/LIDC/"
echo ""