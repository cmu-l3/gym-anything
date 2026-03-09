#!/bin/bash
echo "=== Setting up Lung Lobar Volume Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Clean up any previous outputs
rm -f "$LIDC_DIR/lobar_segmentation.nii.gz" 2>/dev/null || true
rm -f "$LIDC_DIR/lobar_volumes.json" 2>/dev/null || true
rm -f /tmp/lung_lobar_task_result.json 2>/dev/null || true

# Prepare LIDC data
echo "Preparing LIDC chest CT data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

echo "Using patient: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/lung_lobar_patient_id.txt

# Verify DICOM data exists
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
if [ ! -d "$DICOM_DIR" ] || [ "$(find "$DICOM_DIR" -type f | wc -l)" -lt 50 ]; then
    echo "WARNING: LIDC DICOM data not properly downloaded."
    echo "Generating synthetic chest CT for task..."
    
    # Generate synthetic chest CT with lungs
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

lidc_dir = "/home/ga/Documents/SlicerData/LIDC"
gt_dir = "/var/lib/slicer/ground_truth"
patient_id = "LIDC-IDRI-0001"

os.makedirs(lidc_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

np.random.seed(42)

# Create realistic chest CT dimensions
nx, ny, nz = 512, 512, 300
spacing = (0.7, 0.7, 1.5)  # mm per voxel

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize with soft tissue background
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical thorax)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Body mask
body_mask = ((X - center_x)**2 / (180**2) + (Y - center_y)**2 / (120**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create ground truth label map
gt_labels = np.zeros((nx, ny, nz), dtype=np.int16)

# Define lung regions (simplified ellipsoid model)
# Right lung center (anatomical right = patient's right = image left in standard orientation)
right_cx, right_cy = center_x - 70, center_y - 10
# Left lung center
left_cx, left_cy = center_x + 70, center_y - 10

# Create lung parenchyma
lung_start_z = 50   # Start from superior
lung_end_z = 250    # End at diaphragm level

for z in range(lung_start_z, lung_end_z):
    # Lung size varies with z (larger in middle)
    z_factor = 1.0 - 0.5 * ((z - (lung_start_z + lung_end_z) / 2) / ((lung_end_z - lung_start_z) / 2))**2
    z_factor = max(0.3, z_factor)
    
    # Right lung (3 lobes)
    right_rx, right_ry = 60 * z_factor, 80 * z_factor
    right_mask = ((X - right_cx)**2 / right_rx**2 + (Y - right_cy)**2 / right_ry**2) <= 1.0
    
    # Left lung (2 lobes) - slightly smaller due to heart
    left_rx, left_ry = 55 * z_factor, 75 * z_factor
    left_mask = ((X - left_cx)**2 / left_rx**2 + (Y - left_cy)**2 / left_ry**2) <= 1.0
    
    # Set lung HU values
    ct_data[:, :, z][right_mask & body_mask] = np.random.normal(-750, 80, np.sum(right_mask & body_mask)).astype(np.int16)
    ct_data[:, :, z][left_mask & body_mask] = np.random.normal(-750, 80, np.sum(left_mask & body_mask)).astype(np.int16)
    
    # Assign lobe labels based on z position and anatomical divisions
    # Right lung fissures:
    # - Horizontal fissure at ~z=140 separates RUL from RML
    # - Oblique fissure runs diagonally, roughly at y = center_y + (z - 150) * 0.5
    
    oblique_y_right = right_cy + (z - 150) * 0.4
    horizontal_z = 140
    
    if z < horizontal_z:
        # Above horizontal fissure
        upper_mask = (Y < oblique_y_right)
        lower_mask = (Y >= oblique_y_right)
        gt_labels[:, :, z][right_mask & body_mask & upper_mask] = 1  # RUL
        gt_labels[:, :, z][right_mask & body_mask & lower_mask] = 3  # RLL
    else:
        # Below horizontal fissure
        upper_mask = (Y < oblique_y_right)
        middle_mask = (Y >= oblique_y_right) & (Y < oblique_y_right + 30)
        lower_mask = (Y >= oblique_y_right + 30)
        gt_labels[:, :, z][right_mask & body_mask & upper_mask] = 1  # RUL
        gt_labels[:, :, z][right_mask & body_mask & middle_mask] = 2  # RML
        gt_labels[:, :, z][right_mask & body_mask & lower_mask] = 3  # RLL
    
    # Left lung oblique fissure
    oblique_y_left = left_cy + (z - 150) * 0.4
    upper_mask = (Y < oblique_y_left)
    lower_mask = (Y >= oblique_y_left)
    gt_labels[:, :, z][left_mask & body_mask & upper_mask] = 4  # LUL
    gt_labels[:, :, z][left_mask & body_mask & lower_mask] = 5  # LLL

# Add mediastinum (heart, great vessels)
heart_cx, heart_cy = center_x + 30, center_y - 20
for z in range(100, 200):
    z_heart_factor = 1.0 - 0.5 * abs(z - 150) / 50
    heart_rx, heart_ry = 40 * z_heart_factor, 50 * z_heart_factor
    heart_mask = ((X - heart_cx)**2 / max(1, heart_rx)**2 + (Y - heart_cy)**2 / max(1, heart_ry)**2) <= 1.0
    ct_data[:, :, z][heart_mask & body_mask] = np.random.normal(50, 20, np.sum(heart_mask & body_mask)).astype(np.int16)
    # Remove any lung labels in heart region
    gt_labels[:, :, z][heart_mask & body_mask] = 0

# Add spine
spine_cx, spine_cy = center_x, center_y + 100
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 20**2
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 80, np.sum(spine_mask)).astype(np.int16)
    gt_labels[:, :, z][spine_mask] = 0

# Save CT volume
ct_path = os.path.join(lidc_dir, f"{patient_id}_chest_ct.nii.gz")
ct_nii = nib.Nifti1Image(ct_data, affine)
nib.save(ct_nii, ct_path)
print(f"CT saved to {ct_path}")

# Save ground truth segmentation
gt_path = os.path.join(gt_dir, f"{patient_id}_lobar_gt.nii.gz")
gt_nii = nib.Nifti1Image(gt_labels, affine)
nib.save(gt_nii, gt_path)
print(f"Ground truth saved to {gt_path}")

# Calculate ground truth volumes
voxel_volume_mm3 = float(np.prod(spacing))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

lobe_names = {1: "RUL", 2: "RML", 3: "RLL", 4: "LUL", 5: "LLL"}
volumes = {}
centroids = {}

for label, name in lobe_names.items():
    mask = (gt_labels == label)
    voxel_count = np.sum(mask)
    volume_ml = voxel_count * voxel_volume_ml
    volumes[name] = volume_ml
    
    if voxel_count > 0:
        coords = np.array(np.where(mask))
        centroid = coords.mean(axis=1) * np.array(spacing)
        centroids[name] = centroid.tolist()
    else:
        centroids[name] = [0, 0, 0]

total_volume = sum(volumes.values())
right_volume = volumes["RUL"] + volumes["RML"] + volumes["RLL"]
left_volume = volumes["LUL"] + volumes["LLL"]
rl_ratio = right_volume / left_volume if left_volume > 0 else 0

gt_info = {
    "patient_id": patient_id,
    "voxel_spacing_mm": list(spacing),
    "voxel_volume_ml": voxel_volume_ml,
    "volumes_ml": volumes,
    "centroids_mm": centroids,
    "total_lung_volume_ml": total_volume,
    "right_lung_volume_ml": right_volume,
    "left_lung_volume_ml": left_volume,
    "right_left_ratio": rl_ratio,
    "lobe_proportions": {name: vol / total_volume if total_volume > 0 else 0 for name, vol in volumes.items()}
}

gt_info_path = os.path.join(gt_dir, f"{patient_id}_lobar_gt.json")
with open(gt_info_path, "w") as f:
    json.dump(gt_info, f, indent=2)

print(f"Ground truth info saved to {gt_info_path}")
print(f"Total lung volume: {total_volume:.1f} mL")
print(f"R/L ratio: {rl_ratio:.2f}")
for name, vol in volumes.items():
    pct = 100 * vol / total_volume if total_volume > 0 else 0
    print(f"  {name}: {vol:.1f} mL ({pct:.1f}%)")
PYEOF

    PATIENT_ID="LIDC-IDRI-0001"
    CT_FILE="$LIDC_DIR/${PATIENT_ID}_chest_ct.nii.gz"
else
    # Convert DICOM to NIfTI for easier loading
    echo "Converting DICOM to NIfTI..."
    CT_FILE="$LIDC_DIR/${PATIENT_ID}_chest_ct.nii.gz"
    
    if [ ! -f "$CT_FILE" ]; then
        python3 << PYEOF
import os
import sys
try:
    import nibabel as nib
    import numpy as np
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "pydicom"])
    import nibabel as nib
    import numpy as np
    import pydicom

dicom_dir = "$DICOM_DIR"
output_path = "$CT_FILE"

# Load DICOM series
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        fpath = os.path.join(root, f)
        try:
            ds = pydicom.dcmread(fpath, force=True)
            if hasattr(ds, 'pixel_array'):
                dcm_files.append((fpath, ds))
        except:
            continue

if not dcm_files:
    print("No DICOM files found")
    sys.exit(1)

# Sort by instance number or slice location
def get_sort_key(item):
    ds = item[1]
    if hasattr(ds, 'InstanceNumber') and ds.InstanceNumber:
        return int(ds.InstanceNumber)
    if hasattr(ds, 'SliceLocation') and ds.SliceLocation:
        return float(ds.SliceLocation)
    return 0

dcm_files.sort(key=get_sort_key)

# Stack slices
slices = [ds.pixel_array for _, ds in dcm_files]
volume = np.stack(slices, axis=-1)

# Get spacing
ds0 = dcm_files[0][1]
pixel_spacing = list(ds0.PixelSpacing) if hasattr(ds0, 'PixelSpacing') else [1.0, 1.0]
slice_thickness = float(ds0.SliceThickness) if hasattr(ds0, 'SliceThickness') else 1.0
spacing = (float(pixel_spacing[0]), float(pixel_spacing[1]), slice_thickness)

# Apply rescale
intercept = float(ds0.RescaleIntercept) if hasattr(ds0, 'RescaleIntercept') else 0
slope = float(ds0.RescaleSlope) if hasattr(ds0, 'RescaleSlope') else 1
volume = volume * slope + intercept

# Create affine
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Save
nii = nib.Nifti1Image(volume.astype(np.int16), affine)
nib.save(nii, output_path)
print(f"Saved to {output_path}, shape: {volume.shape}")
PYEOF
    fi
fi

# Find the CT file
CT_FILE=""
for path in "$LIDC_DIR/${PATIENT_ID}_chest_ct.nii.gz" "$LIDC_DIR/chest_ct.nii.gz"; do
    if [ -f "$path" ]; then
        CT_FILE="$path"
        break
    fi
done

if [ -z "$CT_FILE" ] || [ ! -f "$CT_FILE" ]; then
    echo "ERROR: Could not find or create chest CT file"
    exit 1
fi

echo "Using CT file: $CT_FILE"

# Create Slicer Python script to load CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
print(f"Loading chest CT: {ct_path}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set lung window/level (W=1500, L=-600)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-600)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on lungs (middle of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with lung window (W=1500, L=-600)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete - ready for lung lobar segmentation task")
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
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/lung_lobar_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Lung Lobar Volume Assessment"
echo "==================================="
echo ""
echo "You are given a chest CT scan. Segment both lungs and divide them into"
echo "the 5 anatomical lobes for surgical planning."
echo ""
echo "Your goals:"
echo "  1. Segment lung parenchyma (HU range: -950 to -250)"
echo "  2. Identify fissures and divide into 5 lobes:"
echo "     - Right Upper Lobe (RUL)"
echo "     - Right Middle Lobe (RML)"
echo "     - Right Lower Lobe (RLL)"  
echo "     - Left Upper Lobe (LUL)"
echo "     - Left Lower Lobe (LLL)"
echo "  3. Calculate volume of each lobe"
echo "  4. Calculate Right/Left volume ratio"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/LIDC/lobar_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/LIDC/lobar_volumes.json"
echo ""