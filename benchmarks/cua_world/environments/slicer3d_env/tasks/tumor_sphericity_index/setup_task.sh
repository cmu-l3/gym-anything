#!/bin/bash
echo "=== Setting up Tumor Sphericity Index Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

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
echo "Using sample: $SAMPLE_ID"

# Verify all required files exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Pre-calculate ground truth shape metrics
echo "Calculating ground truth shape metrics..."
python3 << PYEOF
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

try:
    from scipy import ndimage
    from skimage import measure
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy", "scikit-image"])
    from scipy import ndimage
    from skimage import measure

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"

# Load ground truth
gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Whole tumor = all non-zero labels
whole_tumor = (gt_data > 0).astype(np.uint8)

# Calculate voxel volume
voxel_volume_mm3 = float(np.prod(voxel_dims))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

# Volume
tumor_voxels = int(np.sum(whole_tumor))
volume_mm3 = tumor_voxels * voxel_volume_mm3
volume_ml = volume_mm3 / 1000.0

# Surface area using marching cubes
try:
    # Pad to ensure closed surface
    padded = np.pad(whole_tumor, pad_width=1, mode='constant', constant_values=0)
    verts, faces, _, _ = measure.marching_cubes(padded, level=0.5, spacing=voxel_dims)
    surface_area_mm2 = measure.mesh_surface_area(verts, faces)
except Exception as e:
    print(f"Warning: Could not compute surface area via marching cubes: {e}")
    # Estimate from voxel faces
    # Count boundary voxels
    eroded = ndimage.binary_erosion(whole_tumor)
    boundary = whole_tumor.astype(bool) & ~eroded
    boundary_voxels = np.sum(boundary)
    # Approximate: each boundary voxel contributes ~1 face
    avg_face_area = (voxel_dims[0] * voxel_dims[1] + voxel_dims[1] * voxel_dims[2] + voxel_dims[0] * voxel_dims[2]) / 3
    surface_area_mm2 = boundary_voxels * avg_face_area

# Sphericity = (pi^(1/3) * (6V)^(2/3)) / A
# Where V = volume, A = surface area
if surface_area_mm2 > 0:
    sphericity = (np.pi ** (1/3)) * ((6 * volume_mm3) ** (2/3)) / surface_area_mm2
    sphericity = min(1.0, max(0.0, sphericity))  # Clamp to [0, 1]
else:
    sphericity = 0.0

# Classification
if sphericity > 0.7:
    morphology_class = "Regular"
elif sphericity >= 0.5:
    morphology_class = "Intermediate"
else:
    morphology_class = "Irregular"

# Compute centroid for reference
coords = np.array(np.where(whole_tumor)).T
if len(coords) > 0:
    centroid_voxel = coords.mean(axis=0)
    centroid_mm = centroid_voxel * np.array(voxel_dims)
else:
    centroid_mm = [0, 0, 0]

# Save ground truth shape metrics
gt_shape = {
    "sample_id": sample_id,
    "volume_ml": round(float(volume_ml), 2),
    "volume_mm3": round(float(volume_mm3), 2),
    "surface_area_mm2": round(float(surface_area_mm2), 2),
    "sphericity": round(float(sphericity), 4),
    "morphology_class": morphology_class,
    "tumor_voxels": tumor_voxels,
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "centroid_mm": [float(c) for c in centroid_mm],
}

gt_shape_path = os.path.join(gt_dir, f"{sample_id}_shape_gt.json")
with open(gt_shape_path, 'w') as f:
    json.dump(gt_shape, f, indent=2)

print(f"Ground truth shape metrics saved:")
print(f"  Volume: {volume_ml:.2f} mL")
print(f"  Surface Area: {surface_area_mm2:.2f} mm²")
print(f"  Sphericity: {sphericity:.4f}")
print(f"  Classification: {morphology_class}")
PYEOF

# Clean up any previous task outputs
rm -f /tmp/sphericity_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/agent_tumor_shape.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_shape_report.json" 2>/dev/null || true

# Create a Slicer Python script to load all volumes
cat > /tmp/load_brats_for_shape.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Define volumes to load
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("Loading BraTS MRI volumes for shape analysis...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up views
if loaded_nodes:
    flair_node = slicer.util.getNode("FLAIR") if slicer.util.getNode("FLAIR") else loaded_nodes[0]
    
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center views on data
    bounds = [0]*6
    flair_node.GetBounds(bounds)
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

print("Setup complete - ready for tumor shape analysis")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_for_shape.py > /tmp/slicer_launch.log 2>&1 &

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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/sphericity_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Tumor Shape Analysis - Sphericity Index"
echo "===================================================="
echo ""
echo "You have a brain MRI with a glioma. Your goals:"
echo ""
echo "1. Segment the complete tumor using Segment Editor"
echo "   - FLAIR shows edema/tumor extent"
echo "   - T1_Contrast shows enhancing tumor"
echo ""
echo "2. Use Segment Statistics module to calculate:"
echo "   - Volume (mL)"
echo "   - Surface Area (mm²)"
echo "   - Sphericity (0-1)"
echo ""
echo "3. Create a 3D model of the tumor"
echo ""
echo "4. Save outputs:"
echo "   - Segmentation: ~/Documents/SlicerData/BraTS/agent_tumor_shape.nii.gz"
echo "   - Report: ~/Documents/SlicerData/BraTS/tumor_shape_report.json"
echo ""
echo "Report must include: volume_ml, surface_area_mm2, sphericity,"
echo "morphology_class (Regular/Intermediate/Irregular), clinical_notes"
echo ""
echo "Sphericity Classification:"
echo "  - Regular (>0.7): Round, well-circumscribed"
echo "  - Intermediate (0.5-0.7): Moderately irregular"
echo "  - Irregular (<0.5): Highly irregular, infiltrating"
echo ""