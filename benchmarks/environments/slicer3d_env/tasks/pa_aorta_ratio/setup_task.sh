#!/bin/bash
echo "=== Setting up PA:Aorta Ratio Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task artifacts
rm -f "$LIDC_DIR/pa_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/aorta_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/pa_aorta_report.json" 2>/dev/null || true
rm -f /tmp/pa_aorta_task_result.json 2>/dev/null || true

# ============================================================
# Prepare LIDC chest CT data
# ============================================================
echo "Preparing LIDC-IDRI chest CT data..."

# Check if we already have the data
CT_FILE="$LIDC_DIR/${PATIENT_ID}/chest_ct.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "Attempting to download/prepare LIDC data..."
    
    # Try to run the LIDC preparation script
    if [ -f /workspace/scripts/prepare_lidc_data.sh ]; then
        /workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID" || true
    fi
    
    # Check for DICOM files
    DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
    if [ -d "$DICOM_DIR" ] && [ "$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)" -gt 10 ]; then
        echo "Found DICOM files, converting to NIfTI..."
        
        # Convert DICOM to NIfTI using Python
        python3 << PYEOF
import os
import sys
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "pydicom"])
    import nibabel as nib

import pydicom

dicom_dir = "$DICOM_DIR"
output_path = "$CT_FILE"

print(f"Converting DICOM from {dicom_dir} to NIfTI...")

# Load all DICOM files
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        try:
            fpath = os.path.join(root, f)
            ds = pydicom.dcmread(fpath, force=True)
            if hasattr(ds, 'pixel_array'):
                dcm_files.append((fpath, ds))
        except Exception:
            continue

if not dcm_files:
    print("ERROR: No valid DICOM files found")
    sys.exit(1)

print(f"Found {len(dcm_files)} DICOM slices")

# Sort by instance number or slice location
def get_sort_key(item):
    ds = item[1]
    if hasattr(ds, 'InstanceNumber') and ds.InstanceNumber is not None:
        return int(ds.InstanceNumber)
    if hasattr(ds, 'SliceLocation') and ds.SliceLocation is not None:
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

# Create affine
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Convert to Hounsfield Units if needed
intercept = float(ds0.RescaleIntercept) if hasattr(ds0, 'RescaleIntercept') else 0
slope = float(ds0.RescaleSlope) if hasattr(ds0, 'RescaleSlope') else 1
volume = volume.astype(np.float32) * slope + intercept

# Save
os.makedirs(os.path.dirname(output_path), exist_ok=True)
nii = nib.Nifti1Image(volume.astype(np.int16), affine)
nib.save(nii, output_path)
print(f"Saved to {output_path}")
print(f"Shape: {volume.shape}, Spacing: {spacing}")
PYEOF
    fi
fi

# If still no CT, generate synthetic chest CT data with known vessel structures
if [ ! -f "$CT_FILE" ]; then
    echo "Generating synthetic chest CT with PA and Aorta structures..."
    
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

# Create realistic chest CT dimensions
nx, ny, nz = 512, 512, 150
spacing = (0.7, 0.7, 2.5)  # mm per voxel (typical chest CT)

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize CT volume with air (-1000 HU)
ct_data = np.ones((nx, ny, nz), dtype=np.int16) * -1000

# Create coordinate grids
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Create body outline (elliptical thorax shape)
body_a, body_b = 180, 130  # Semi-axes for thorax
body_mask = ((X - center_x)**2 / (body_a**2) + (Y - center_y)**2 / (body_b**2)) <= 1.0

# Fill body with soft tissue
for z in range(nz):
    ct_data[:, :, z][body_mask] = np.random.normal(40, 15, (np.sum(body_mask),)).astype(np.int16)

# Create lung regions (dark air pockets)
lung_r_cx, lung_r_cy = center_x + 60, center_y - 20
lung_l_cx, lung_l_cy = center_x - 60, center_y - 20

for z in range(20, nz - 20):
    # Right lung
    lung_r_mask = ((X - lung_r_cx)**2 / (70**2) + (Y - lung_r_cy)**2 / (90**2)) <= 1.0
    ct_data[:, :, z][lung_r_mask & body_mask] = np.random.normal(-800, 50, (np.sum(lung_r_mask & body_mask),)).astype(np.int16)
    
    # Left lung
    lung_l_mask = ((X - lung_l_cx)**2 / (65**2) + (Y - lung_l_cy)**2 / (85**2)) <= 1.0
    ct_data[:, :, z][lung_l_mask & body_mask] = np.random.normal(-800, 50, (np.sum(lung_l_mask & body_mask),)).astype(np.int16)

# Create spine (posterior, bright)
spine_cx, spine_cy = center_x, center_y + 80
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 15**2
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 50, (np.sum(spine_mask),)).astype(np.int16)

# ============================================================
# Create Main Pulmonary Artery (MPA)
# Location: Anterior mediastinum, slight left of midline
# Normal diameter: 25-29mm, we'll make it 31mm (slightly elevated)
# ============================================================
mpa_cx = center_x - 15  # Slightly left of midline
mpa_cy = center_y - 40  # Anterior
mpa_diameter_mm = 31.0  # Slightly elevated
mpa_radius_voxels = (mpa_diameter_mm / 2.0) / spacing[0]

# MPA bifurcation level (around slice 60-80)
bifurcation_slice = 70

# MPA structure - cylindrical vessel
for z in range(40, 100):
    # Vary diameter slightly along z
    if z < bifurcation_slice:
        current_radius = mpa_radius_voxels
    else:
        # Branches get smaller above bifurcation
        current_radius = mpa_radius_voxels * 0.7
    
    mpa_mask = ((X - mpa_cx)**2 + (Y - mpa_cy)**2) <= current_radius**2
    # Blood pool with contrast: ~150-200 HU
    ct_data[:, :, z][mpa_mask & body_mask] = np.random.normal(170, 25, (np.sum(mpa_mask & body_mask),)).astype(np.int16)

# ============================================================
# Create Ascending Aorta
# Location: Posterior and right of MPA
# Normal diameter: 28-34mm, we'll make it 32mm (normal)
# ============================================================
aorta_cx = center_x + 10  # Right of midline
aorta_cy = center_y - 25  # Slightly anterior
aorta_diameter_mm = 32.0  # Normal
aorta_radius_voxels = (aorta_diameter_mm / 2.0) / spacing[0]

# Ascending aorta - cylindrical vessel
for z in range(30, 110):
    # Slight variation in diameter
    current_radius = aorta_radius_voxels * (1.0 + 0.05 * np.sin(z / 10))
    
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= current_radius**2
    # Contrast-enhanced blood: ~180-220 HU
    ct_data[:, :, z][aorta_mask & body_mask] = np.random.normal(200, 25, (np.sum(aorta_mask & body_mask),)).astype(np.int16)

# ============================================================
# Create Descending Aorta
# Location: Left posterior thorax
# ============================================================
desc_aorta_cx = center_x - 35
desc_aorta_cy = center_y + 60
desc_aorta_radius = 12 / spacing[0]  # ~24mm diameter

for z in range(10, nz - 10):
    desc_mask = ((X - desc_aorta_cx)**2 + (Y - desc_aorta_cy)**2) <= desc_aorta_radius**2
    ct_data[:, :, z][desc_mask & body_mask] = np.random.normal(190, 25, (np.sum(desc_mask & body_mask),)).astype(np.int16)

# Add some mediastinal structures (heart, etc.)
heart_cx, heart_cy = center_x - 20, center_y + 10
for z in range(40, 90):
    heart_mask = ((X - heart_cx)**2 / (60**2) + (Y - heart_cy)**2 / (50**2)) <= 1.0
    # Don't overwrite vessels
    mpa_region = ((X - mpa_cx)**2 + (Y - mpa_cy)**2) <= (mpa_radius_voxels * 1.2)**2
    aorta_region = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= (aorta_radius_voxels * 1.2)**2
    heart_only = heart_mask & ~mpa_region & ~aorta_region
    ct_data[:, :, z][heart_only & body_mask] = np.random.normal(60, 20, (np.sum(heart_only & body_mask),)).astype(np.int16)

# Clip to valid HU range
ct_data = np.clip(ct_data, -1024, 3071)

# ============================================================
# Save CT volume
# ============================================================
patient_dir = os.path.join(lidc_dir, patient_id)
os.makedirs(patient_dir, exist_ok=True)

ct_path = os.path.join(patient_dir, "chest_ct.nii.gz")
ct_nii = nib.Nifti1Image(ct_data, affine)
nib.save(ct_nii, ct_path)
print(f"CT volume saved to {ct_path}")
print(f"Shape: {ct_data.shape}, Spacing: {spacing}")

# ============================================================
# Calculate ground truth measurements
# ============================================================
pa_aorta_ratio = mpa_diameter_mm / aorta_diameter_mm

if pa_aorta_ratio < 1.0:
    classification = "Normal"
elif pa_aorta_ratio <= 1.3:
    classification = "Elevated"
else:
    classification = "Significantly elevated"

gt_data = {
    "patient_id": patient_id,
    "pa_diameter_mm": float(mpa_diameter_mm),
    "aorta_diameter_mm": float(aorta_diameter_mm),
    "pa_aorta_ratio": float(round(pa_aorta_ratio, 3)),
    "classification": classification,
    "bifurcation_slice": bifurcation_slice,
    "pa_center_voxels": [int(mpa_cx), int(mpa_cy)],
    "aorta_center_voxels": [int(aorta_cx), int(aorta_cy)],
    "voxel_spacing_mm": list(spacing),
    "measurement_level_z_mm": float(bifurcation_slice * spacing[2]),
    "data_type": "synthetic"
}

os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{patient_id}_pa_aorta_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"PA diameter: {mpa_diameter_mm:.1f} mm")
print(f"Aorta diameter: {aorta_diameter_mm:.1f} mm")
print(f"PA:Ao ratio: {pa_aorta_ratio:.3f}")
print(f"Classification: {classification}")
PYEOF
fi

# Set environment variables for Python scripts
export LIDC_DIR GROUND_TRUTH_DIR PATIENT_ID

# Save patient ID for later scripts
echo "$PATIENT_ID" > /tmp/lidc_patient_id.txt

# Verify CT exists
CT_FILE="$LIDC_DIR/${PATIENT_ID}/chest_ct.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi
echo "CT file ready: $CT_FILE"

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_pa_aorta_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth not found at $GT_FILE"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# ============================================================
# Launch 3D Slicer with the chest CT
# ============================================================

# Create Slicer Python script to load the CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
patient_id = "$PATIENT_ID"

print(f"Loading chest CT scan: {patient_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set mediastinal window/level (good for vessels)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Mediastinal window: W=400, L=40
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate PA bifurcation level (middle of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Set axial view to middle of volume (where PA bifurcation typically is)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with mediastinal window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Navigate to PA bifurcation level to measure PA and Aorta")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for PA:Aorta ratio measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
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
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/pa_aorta_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Pulmonary Artery to Aorta Ratio Assessment"
echo "================================================="
echo ""
echo "You have a chest CT scan. Your goal is to measure the PA:Ao ratio"
echo "for pulmonary hypertension screening."
echo ""
echo "Instructions:"
echo "  1. Navigate to the PA bifurcation level (where MPA splits)"
echo "  2. Measure the main pulmonary artery (MPA) diameter"
echo "     - Located anterior, slightly left of midline"
echo "     - Use Markups ruler, measure perpendicular to vessel"
echo "  3. Measure the ascending aorta diameter"
echo "     - Located posterior and right of MPA"
echo "  4. Calculate PA:Ao ratio and classify:"
echo "     - Normal: < 1.0"
echo "     - Elevated: 1.0 - 1.3"
echo "     - Significantly elevated: > 1.3"
echo ""
echo "Save outputs to:"
echo "  - PA markup: ~/Documents/SlicerData/LIDC/pa_measurement.mrk.json"
echo "  - Aorta markup: ~/Documents/SlicerData/LIDC/aorta_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/pa_aorta_report.json"
echo ""