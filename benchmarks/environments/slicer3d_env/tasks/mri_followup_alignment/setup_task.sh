#!/bin/bash
echo "=== Setting up MRI Follow-up Alignment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
BASELINE_FLAIR="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"

echo "Using sample: $SAMPLE_ID"
echo "Baseline FLAIR: $BASELINE_FLAIR"

# Verify baseline exists
if [ ! -f "$BASELINE_FLAIR" ]; then
    echo "ERROR: Baseline FLAIR not found at $BASELINE_FLAIR"
    exit 1
fi

# Clean up any previous task outputs
rm -f "$BRATS_DIR/followup_flair_misaligned.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/followup_registered.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/followup_transform.h5" 2>/dev/null || true
rm -f "$BRATS_DIR/followup_report.json" 2>/dev/null || true
rm -f /tmp/followup_alignment_result.json 2>/dev/null || true

# Create misaligned follow-up with known transformation
echo "Creating misaligned follow-up scan..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Install dependencies if needed
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
    import nibabel as nib

from scipy.ndimage import affine_transform

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

baseline_path = f"{brats_dir}/{sample_id}/{sample_id}_flair.nii.gz"
output_path = f"{brats_dir}/followup_flair_misaligned.nii.gz"
gt_json_path = f"{gt_dir}/followup_gt.json"

print(f"Loading baseline: {baseline_path}")
baseline_nii = nib.load(baseline_path)
baseline_data = baseline_nii.get_fdata()
baseline_affine = baseline_nii.affine
voxel_dims = baseline_nii.header.get_zooms()[:3]

print(f"Baseline shape: {baseline_data.shape}")
print(f"Voxel dimensions: {voxel_dims}")

# Generate random misalignment transformation
# Use system random for unpredictability
np.random.seed(int.from_bytes(os.urandom(4), 'big') % (2**31))

# Rotation angles (degrees) - random within ±10 degrees per axis
rx = np.random.uniform(-10, 10)
ry = np.random.uniform(-10, 10)
rz = np.random.uniform(-10, 10)

# Translation (mm) - random within ±10mm per axis
tx = np.random.uniform(-10, 10)
ty = np.random.uniform(-10, 10)
tz = np.random.uniform(-10, 10)

print(f"Applied rotation (deg): [{rx:.2f}, {ry:.2f}, {rz:.2f}]")
print(f"Applied translation (mm): [{tx:.2f}, {ty:.2f}, {tz:.2f}]")

# Convert to radians
rx_rad = np.deg2rad(rx)
ry_rad = np.deg2rad(ry)
rz_rad = np.deg2rad(rz)

# Rotation matrices
Rx = np.array([
    [1, 0, 0],
    [0, np.cos(rx_rad), -np.sin(rx_rad)],
    [0, np.sin(rx_rad), np.cos(rx_rad)]
])

Ry = np.array([
    [np.cos(ry_rad), 0, np.sin(ry_rad)],
    [0, 1, 0],
    [-np.sin(ry_rad), 0, np.cos(ry_rad)]
])

Rz = np.array([
    [np.cos(rz_rad), -np.sin(rz_rad), 0],
    [np.sin(rz_rad), np.cos(rz_rad), 0],
    [0, 0, 1]
])

# Combined rotation matrix
R = Rz @ Ry @ Rx

# Convert translation from mm to voxels
tx_vox = tx / voxel_dims[0]
ty_vox = ty / voxel_dims[1]
tz_vox = tz / voxel_dims[2]

# Rotation center (center of volume)
center = np.array(baseline_data.shape) / 2.0

# Apply transformation around center
offset = center - R @ center + np.array([tx_vox, ty_vox, tz_vox])

print(f"Applying affine transformation...")
misaligned_data = affine_transform(
    baseline_data,
    R,
    offset=offset,
    order=1,
    mode='constant',
    cval=0
)

# Save misaligned follow-up
misaligned_nii = nib.Nifti1Image(misaligned_data.astype(np.float32), baseline_affine, baseline_nii.header)
nib.save(misaligned_nii, output_path)
print(f"Misaligned follow-up saved to: {output_path}")

# Calculate tumor info from ground truth if available
tumor_diameter = 0.0
gt_seg_path = f"{gt_dir}/{sample_id}_seg.nii.gz"
if os.path.exists(gt_seg_path):
    try:
        seg_nii = nib.load(gt_seg_path)
        seg_data = seg_nii.get_fdata()
        tumor_mask = (seg_data > 0)
        
        if np.any(tumor_mask):
            coords = np.argwhere(tumor_mask)
            mins = coords.min(axis=0)
            maxs = coords.max(axis=0)
            extents_mm = (maxs - mins) * np.array(voxel_dims)
            tumor_diameter = float(np.max(extents_mm))
            print(f"Tumor max diameter from GT: {tumor_diameter:.1f} mm")
    except Exception as e:
        print(f"Could not load GT segmentation: {e}")

# Save ground truth transformation for verification
gt_data = {
    "sample_id": sample_id,
    "applied_rotation_deg": [float(rx), float(ry), float(rz)],
    "applied_translation_mm": [float(tx), float(ty), float(tz)],
    "rotation_center_voxels": center.tolist(),
    "voxel_dimensions_mm": [float(v) for v in voxel_dims],
    "expected_inverse_rotation_deg": [float(-rx), float(-ry), float(-rz)],
    "expected_inverse_translation_mm": [float(-tx), float(-ty), float(-tz)],
    "tumor_max_diameter_mm": tumor_diameter,
    "baseline_path": baseline_path,
    "misaligned_path": output_path,
    "rotation_matrix": R.tolist()
}

os.makedirs(gt_dir, exist_ok=True)
with open(gt_json_path, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to: {gt_json_path}")

print("Misalignment transformation created successfully!")
PYEOF

# Export environment variables for Python script
export SAMPLE_ID BRATS_DIR GROUND_TRUTH_DIR

# Verify misaligned file was created
if [ ! -f "$BRATS_DIR/followup_flair_misaligned.nii.gz" ]; then
    echo "ERROR: Failed to create misaligned follow-up"
    exit 1
fi
echo "Misaligned follow-up created successfully"

# Verify ground truth was saved
if [ ! -f "$GROUND_TRUTH_DIR/followup_gt.json" ]; then
    echo "ERROR: Failed to save ground truth"
    exit 1
fi

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Create Slicer Python script to load ONLY the baseline
cat > /tmp/load_baseline_flair.py << PYEOF
import slicer
import os

baseline_path = "$BASELINE_FLAIR"
sample_id = "$SAMPLE_ID"

print(f"Loading baseline FLAIR: {baseline_path}")

# Load baseline volume
volume_node = slicer.util.loadVolume(baseline_path)

if volume_node:
    volume_node.SetName("Baseline_FLAIR")
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Center on data
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
    
    print(f"Baseline FLAIR loaded: {volume_node.GetName()}")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("ERROR: Could not load baseline volume")

print("")
print("Task: Load the follow-up MRI and register it to this baseline")
print("Follow-up location: ~/Documents/SlicerData/BraTS/followup_flair_misaligned.nii.gz")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with baseline only
echo "Launching 3D Slicer with baseline FLAIR..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_baseline_flair.py > /tmp/slicer_launch.log 2>&1 &

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
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: MRI Follow-up Alignment for Lesion Comparison"
echo "===================================================="
echo ""
echo "The baseline FLAIR MRI is loaded. A follow-up scan from 6 months later"
echo "is available but MISALIGNED due to different patient positioning."
echo ""
echo "Your goal:"
echo "  1. Load ~/Documents/SlicerData/BraTS/followup_flair_misaligned.nii.gz"
echo "  2. Register it to the baseline using RIGID registration"
echo "  3. Verify alignment visually"
echo "  4. Measure lesion diameter in both scans"
echo "  5. Save transform, registered volume, and report"
echo ""
echo "Output files to create:"
echo "  - ~/Documents/SlicerData/BraTS/followup_transform.h5"
echo "  - ~/Documents/SlicerData/BraTS/followup_registered.nii.gz"
echo "  - ~/Documents/SlicerData/BraTS/followup_report.json"
echo ""