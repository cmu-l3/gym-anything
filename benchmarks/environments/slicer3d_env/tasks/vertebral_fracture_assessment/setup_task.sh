#!/bin/bash
echo "=== Setting up Vertebral Fracture Assessment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

SPINE_DIR="/home/ga/Documents/SlicerData/Spine"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
FRACTURED_LEVEL="L1"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create directories
mkdir -p "$SPINE_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga "$SPINE_DIR" 2>/dev/null || true

# Clear any previous task artifacts
rm -f "$SPINE_DIR/vertebral_measurements.mrk.json" 2>/dev/null || true
rm -f "$SPINE_DIR/fracture_report.json" 2>/dev/null || true
rm -f /tmp/vertebral_task_result.json 2>/dev/null || true

# ============================================================
# PREPARE SPINE CT DATA
# ============================================================
echo "Preparing spine CT data..."

# Check if data already exists
if [ -f "$SPINE_DIR/spine_ct.nii.gz" ] && [ -f "$GROUND_TRUTH_DIR/spine_fracture_gt.json" ]; then
    echo "Spine CT data already exists"
else
    echo "Generating synthetic thoracolumbar spine CT with compression fracture..."
    
    # Ensure Python dependencies
    pip install -q numpy nibabel scipy 2>/dev/null || pip3 install -q numpy nibabel scipy 2>/dev/null || true

    export SPINE_DIR GROUND_TRUTH_DIR FRACTURED_LEVEL
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

from scipy.ndimage import gaussian_filter

spine_dir = os.environ.get("SPINE_DIR", "/home/ga/Documents/SlicerData/Spine")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
fractured_level = os.environ.get("FRACTURED_LEVEL", "L1")

np.random.seed(42)

# ============================================================
# Spine CT Parameters
# ============================================================
nx, ny, nz = 256, 256, 150
spacing = (0.78125, 0.78125, 2.0)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]
affine[0, 3] = -nx * spacing[0] / 2
affine[1, 3] = -ny * spacing[1] / 2
affine[2, 3] = -nz * spacing[2] / 2

# ============================================================
# Generate CT Volume
# ============================================================
ct_data = np.zeros((nx, ny, nz), dtype=np.int16)
ct_data[:] = -1000  # Air

# Create body outline (elliptical soft tissue)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_mask = ((X - center_x)**2 / (90**2) + (Y - center_y)**2 / (70**2)) <= 1.0

# Fill body with soft tissue
for z in range(nz):
    ct_data[:, :, z][body_mask] = np.random.normal(40, 10, (np.sum(body_mask),)).astype(np.int16)

# ============================================================
# Define vertebral levels (T10-L5)
# ============================================================
vertebrae = {
    'T10': {'z_start': 135, 'z_end': 145, 'height_normal': 22},
    'T11': {'z_start': 120, 'z_end': 133, 'height_normal': 23},
    'T12': {'z_start': 103, 'z_end': 118, 'height_normal': 24},
    'L1':  {'z_start': 85, 'z_end': 101, 'height_normal': 26},
    'L2':  {'z_start': 67, 'z_end': 83, 'height_normal': 27},
    'L3':  {'z_start': 48, 'z_end': 65, 'height_normal': 28},
    'L4':  {'z_start': 28, 'z_end': 46, 'height_normal': 28},
    'L5':  {'z_start': 8, 'z_end': 26, 'height_normal': 27},
}

# Fracture parameters - Grade 2 (Moderate) wedge fracture
fracture_level = fractured_level.upper()
fracture_anterior_reduction = 0.31  # 31% reduction -> Grade 2 (Moderate)
fracture_morphology = "wedge"

# Vertebral body dimensions
vertebra_width_mm = 45
vertebra_depth_mm = 35
vertebra_width_vox = vertebra_width_mm / spacing[0]
vertebra_depth_vox = vertebra_depth_mm / spacing[1]

# Position of vertebral body center
vert_center_x = center_x
vert_center_y = center_y + 30  # Posterior

# ============================================================
# Create each vertebra
# ============================================================
ground_truth = {}

for level, params in vertebrae.items():
    z_start = params['z_start']
    z_end = params['z_end']
    normal_height = params['height_normal']
    
    is_fractured = (level == fracture_level)
    
    if is_fractured:
        anterior_height = normal_height * (1 - fracture_anterior_reduction)
        posterior_height = normal_height
        print(f"Creating fractured {level}: Ha={anterior_height:.1f}mm, Hp={posterior_height:.1f}mm")
    else:
        anterior_height = normal_height
        posterior_height = normal_height
    
    # Create vertebral body
    for z in range(z_start, min(z_end, nz)):
        z_relative = (z - z_start) / max(1, (z_end - z_start))
        
        vert_mask = ((X - vert_center_x)**2 / (vertebra_width_vox/2)**2 + 
                     (Y - vert_center_y)**2 / (vertebra_depth_vox/2)**2) <= 1.0
        
        cortical_inner = ((X - vert_center_x)**2 / ((vertebra_width_vox/2 - 2)**2) + 
                         (Y - vert_center_y)**2 / ((vertebra_depth_vox/2 - 2)**2)) <= 1.0
        cortical_shell = vert_mask & ~cortical_inner
        
        # For fractured vertebra, create wedge deformity in upper slices
        if is_fractured and z_relative > 0.6:
            y_frac = (Y - (vert_center_y - vertebra_depth_vox/2)) / vertebra_depth_vox
            anterior_mask = Y < vert_center_y
            height_factor = 1.0 - fracture_anterior_reduction * (1 - y_frac.clip(0, 1))
            deform_mask = height_factor > (z_relative - 0.6) / 0.4
            vert_mask = vert_mask & (deform_mask | ~anterior_mask)
        
        if vert_mask.any():
            ct_data[:, :, z][cortical_shell & body_mask] = np.random.normal(
                700, 100, (np.sum(cortical_shell & body_mask),)).astype(np.int16)
            ct_data[:, :, z][cortical_inner & vert_mask & body_mask] = np.random.normal(
                200, 50, (np.sum(cortical_inner & vert_mask & body_mask),)).astype(np.int16)
    
    if is_fractured:
        ground_truth = {
            'vertebral_level': level,
            'anterior_height_mm': round(anterior_height, 1),
            'posterior_height_mm': round(posterior_height, 1),
            'compression_ratio': round(anterior_height / posterior_height, 2),
            'genant_grade': 2,
            'morphology': fracture_morphology,
            'z_slice_center': (z_start + z_end) // 2,
            'normal_height_mm': normal_height,
            'height_reduction_percent': round(fracture_anterior_reduction * 100, 0)
        }

# Add spinous processes
for level, params in vertebrae.items():
    z_start = params['z_start']
    z_end = params['z_end']
    for z in range(z_start + 2, min(z_end - 2, nz)):
        sp_mask = ((X - vert_center_x)**2 <= 3**2) & \
                  (Y > vert_center_y + vertebra_depth_vox/2) & \
                  (Y < vert_center_y + vertebra_depth_vox/2 + 15)
        ct_data[:, :, z][sp_mask & body_mask] = np.random.normal(
            500, 100, (np.sum(sp_mask & body_mask),)).astype(np.int16)

# Smooth and finalize
ct_data = gaussian_filter(ct_data.astype(np.float32), sigma=0.5).astype(np.int16)
ct_data[~np.broadcast_to(body_mask[..., np.newaxis], ct_data.shape)] = -1000

# ============================================================
# Save files
# ============================================================
os.makedirs(spine_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(spine_dir, "spine_ct.nii.gz")
nib.save(ct_img, ct_path)
print(f"Spine CT saved: {ct_path}")

gt_path = os.path.join(gt_dir, "spine_fracture_gt.json")
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved: {gt_path}")
print(f"Fracture: {fracture_level}")
print(f"  Anterior height: {ground_truth['anterior_height_mm']} mm")
print(f"  Posterior height: {ground_truth['posterior_height_mm']} mm")
print(f"  Compression ratio: {ground_truth['compression_ratio']}")
print(f"  Genant grade: {ground_truth['genant_grade']}")
PYEOF
fi

# Set permissions
chown -R ga:ga "$SPINE_DIR" 2>/dev/null || true
chmod -R 755 "$SPINE_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

CT_FILE="$SPINE_DIR/spine_ct.nii.gz"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/spine_fracture_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# ============================================================
# LAUNCH 3D SLICER
# ============================================================

# Create a Slicer Python script to load the CT with bone window
cat > /tmp/load_spine_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/Spine/spine_ct.nii.gz"

print("Loading spine CT scan...")
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("SpineCT")
    
    # Set bone window/level for optimal spine visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Bone window: W=1500, L=300 (good for vertebral structure)
        displayNode.SetWindow(1500)
        displayNode.SetLevel(300)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Set initial slice positions to show spine
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on the data
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Yellow - Sagittal (best for spine)
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with bone window (W=1500, L=300)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Use sagittal (Yellow) view for best vertebral height visualization")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for vertebral fracture assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with spine CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_spine_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal agent interaction
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for CT to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/spine_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Vertebral Compression Fracture Assessment"
echo "================================================"
echo ""
echo "You are given a thoracolumbar spine CT of an elderly patient"
echo "who fell and has osteoporosis. Evaluate for compression fractures."
echo ""
echo "Your goal:"
echo "  1. Navigate to the thoracolumbar spine (T10-L5)"
echo "  2. Use sagittal view for best height visualization"
echo "  3. Find the vertebra with reduced anterior height"
echo "  4. Measure anterior height (Ha) with Markups ruler"
echo "  5. Measure posterior height (Hp) with Markups ruler"
echo "  6. Calculate compression ratio (Ha/Hp)"
echo "  7. Assign Genant grade (0-3)"
echo ""
echo "Genant Classification:"
echo "  Grade 0: Normal (<20% reduction)"
echo "  Grade 1: Mild (20-25% reduction)"
echo "  Grade 2: Moderate (26-40% reduction)"
echo "  Grade 3: Severe (>40% reduction)"
echo ""
echo "Save your outputs:"
echo "  - Measurements: ~/Documents/SlicerData/Spine/vertebral_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/Spine/fracture_report.json"
echo ""