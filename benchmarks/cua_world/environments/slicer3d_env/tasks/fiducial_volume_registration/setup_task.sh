#!/bin/bash
echo "=== Setting up Fiducial Volume Registration Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
TASK_DATA_DIR="/home/ga/Documents/SlicerData/RegistrationTask"

mkdir -p "$TASK_DATA_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Ensure sample data exists
if [ ! -f "$SAMPLE_DIR/MRHead.nrrd" ]; then
    echo "MRHead.nrrd not found. Attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$SAMPLE_DIR/MRHead.nrrd" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$SAMPLE_DIR/MRHead.nrrd" ] || [ $(stat -c%s "$SAMPLE_DIR/MRHead.nrrd" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "ERROR: Could not download MRHead sample data"
        exit 1
    fi
    
    chown -R ga:ga "$SAMPLE_DIR"
fi

echo "Source data: $SAMPLE_DIR/MRHead.nrrd"

# Copy reference volume
cp "$SAMPLE_DIR/MRHead.nrrd" "$TASK_DATA_DIR/MRHead_reference.nrrd"
echo "Created reference volume"

# Create misaligned volume with known transformation
echo "Creating misaligned volume with known transformation..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
for pkg in ['pynrrd', 'scipy']:
    try:
        if pkg == 'pynrrd':
            import nrrd
        else:
            import scipy
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", pkg])

import nrrd
from scipy.ndimage import affine_transform
from scipy.spatial.transform import Rotation

sample_dir = "/home/ga/Documents/SlicerData/SampleData"
task_dir = "/home/ga/Documents/SlicerData/RegistrationTask"
gt_dir = "/var/lib/slicer/ground_truth"

# Load reference volume
print("Loading MRHead.nrrd...")
data, header = nrrd.read(os.path.join(sample_dir, "MRHead.nrrd"))
print(f"Volume shape: {data.shape}, dtype: {data.dtype}")

# Define the misalignment transformation
# Translation in mm
translation_mm = np.array([12.0, -8.0, 5.0])

# Rotation: 8 degrees around Z (SI axis), 3 degrees around X (LR axis)
rotation_deg = np.array([3.0, 0.0, 8.0])  # degrees around X, Y, Z axes
rotation_rad = np.deg2rad(rotation_deg)

# Get voxel spacing from header
spacing = np.array([1.0, 1.0, 1.0])
try:
    space_dirs = header.get('space directions', None)
    if space_dirs is not None:
        valid_dirs = []
        for sd in space_dirs:
            if sd is not None and not (isinstance(sd, str) and sd.lower() == 'none'):
                valid_dirs.append(np.linalg.norm(sd))
        if len(valid_dirs) >= 3:
            spacing = np.array(valid_dirs[:3])
except Exception as e:
    print(f"Warning: Could not parse spacing: {e}")

print(f"Voxel spacing: {spacing} mm")

# Convert translation to voxel units
translation_voxels = translation_mm / spacing

# Create rotation matrix
r = Rotation.from_euler('xyz', rotation_rad)
rotation_matrix = r.as_matrix()

# Center of volume for rotation
center = np.array(data.shape) / 2.0

# Create affine transformation
# output[i] = input[R @ (i - center) + center + translation]
# => output[i] = input[R @ i + (-R @ center + center + translation)]
offset = -rotation_matrix @ center + center + translation_voxels

# Apply transformation to create misaligned volume
print("Applying transformation...")
misaligned_data = affine_transform(
    data,
    rotation_matrix,
    offset=offset,
    order=1,
    mode='constant',
    cval=0
)

# Save misaligned volume
output_path = os.path.join(task_dir, "MRHead_misaligned.nrrd")
nrrd.write(output_path, misaligned_data.astype(data.dtype), header)
print(f"Saved misaligned volume to {output_path}")

# Compute inverse transform (what the agent needs to find)
inverse_rotation = rotation_matrix.T
inverse_translation = -inverse_rotation @ translation_mm

# Save ground truth
ground_truth = {
    "applied_transform": {
        "translation_mm": translation_mm.tolist(),
        "rotation_deg": rotation_deg.tolist(),
        "rotation_matrix": rotation_matrix.tolist(),
        "center_voxels": center.tolist(),
        "spacing_mm": spacing.tolist()
    },
    "expected_inverse": {
        "translation_mm": inverse_translation.tolist(),
        "rotation_deg": (-rotation_deg).tolist(),
        "rotation_matrix": inverse_rotation.tolist()
    },
    "registration_tolerance": {
        "max_fre_mm": 3.0,
        "max_rotation_error_deg": 2.0,
        "max_translation_error_mm": 2.0
    }
}

gt_path = os.path.join(gt_dir, "registration_gt.json")
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)
print(f"Saved ground truth to {gt_path}")

print("Misaligned volume creation complete!")
print(f"Applied transform: translation={translation_mm}, rotation={rotation_deg} deg")
PYEOF

# Verify files were created
if [ ! -f "$TASK_DATA_DIR/MRHead_reference.nrrd" ]; then
    echo "ERROR: Reference volume not created"
    exit 1
fi

if [ ! -f "$TASK_DATA_DIR/MRHead_misaligned.nrrd" ]; then
    echo "ERROR: Misaligned volume not created"
    exit 1
fi

# Set permissions
chown -R ga:ga "$TASK_DATA_DIR"
chmod -R 755 "$TASK_DATA_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Record initial state - no transforms/fiducials should exist yet
echo "0" > /tmp/initial_transform_count.txt
echo "0" > /tmp/initial_fiducial_count.txt

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load both volumes
LOAD_SCRIPT="/tmp/load_registration_volumes.py"
cat > "$LOAD_SCRIPT" << 'LOADPY'
import slicer
import os

task_dir = "/home/ga/Documents/SlicerData/RegistrationTask"

print("Loading volumes for registration task...")

# Load reference volume
ref_path = os.path.join(task_dir, "MRHead_reference.nrrd")
print(f"Loading reference: {ref_path}")
ref_node = slicer.util.loadVolume(ref_path)
ref_node.SetName("MRHead_reference")

# Load misaligned volume
mis_path = os.path.join(task_dir, "MRHead_misaligned.nrrd")
print(f"Loading misaligned: {mis_path}")
mis_node = slicer.util.loadVolume(mis_path)
mis_node.SetName("MRHead_misaligned")

# Set up visualization - reference in background, misaligned in foreground
layoutManager = slicer.app.layoutManager()
for sliceViewName in ['Red', 'Green', 'Yellow']:
    sliceWidget = layoutManager.sliceWidget(sliceViewName)
    sliceLogic = sliceWidget.sliceLogic()
    sliceCompositeNode = sliceLogic.GetSliceCompositeNode()
    sliceCompositeNode.SetBackgroundVolumeID(ref_node.GetID())
    sliceCompositeNode.SetForegroundVolumeID(mis_node.GetID())
    sliceCompositeNode.SetForegroundOpacity(0.5)

# Reset views and center
slicer.util.resetSliceViews()

# Set to axial view centered
red_logic = layoutManager.sliceWidget('Red').sliceLogic()
red_logic.SetSliceOffset(0)

print("")
print("=" * 60)
print("VOLUMES LOADED - Notice the misalignment!")
print("=" * 60)
print("Background (dim): MRHead_reference (fixed)")
print("Foreground (bright, 50% opacity): MRHead_misaligned (moving)")
print("")
print("TASK: Use Fiducial Registration Wizard to align them")
print("  1. Go to Modules > Registration > Fiducial Registration Wizard")
print("  2. Place 4+ corresponding landmarks on both volumes")
print("  3. Compute Rigid registration")
print("  4. Apply transform to moving volume")
print("=" * 60)
LOADPY

chmod 644 "$LOAD_SCRIPT"

# Launch Slicer with the loading script
echo "Launching 3D Slicer and loading volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$LOAD_SCRIPT" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for script execution
sleep 8

# Maximize and focus window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    echo "Maximizing Slicer window: $SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
else
    echo "Warning: Could not find Slicer window ID"
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial_state.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Two volumes are loaded and overlaid:"
echo "  - MRHead_reference (fixed/target - background)"
echo "  - MRHead_misaligned (moving - foreground, 50% opacity)"
echo ""
echo "The volumes are visibly misaligned (~15mm translation, ~8° rotation)"
echo ""
echo "Task: Use Fiducial Registration Wizard to register them"
echo "  - Place 4+ corresponding anatomical landmarks"
echo "  - Achieve FRE < 3.0 mm"