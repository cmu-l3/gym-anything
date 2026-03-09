#!/bin/bash
echo "=== Setting up Tumor-to-Ventricle Proximity Assessment Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

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

# Verify all required MRI files exist
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

# Verify ground truth segmentation exists (hidden from agent)
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous task outputs
rm -f /tmp/proximity_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/ventricle_distance.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/proximity_report.json" 2>/dev/null || true

# Compute ground truth distance from tumor to ventricles
echo "Computing ground truth tumor-ventricle distance..."
python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    from scipy.ndimage import binary_dilation, binary_erosion, distance_transform_edt
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import binary_dilation, binary_erosion, distance_transform_edt

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
sample_dir = os.environ.get("SAMPLE_DIR", f"/home/ga/Documents/SlicerData/BraTS/{sample_id}")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

print(f"Processing sample: {sample_id}")

# Load ground truth tumor segmentation
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
gt_nii = nib.load(gt_seg_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]
affine = gt_nii.affine

print(f"Segmentation shape: {gt_data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")

# Load T2 image for ventricle identification
t2_path = os.path.join(sample_dir, f"{sample_id}_t2.nii.gz")
t2_nii = nib.load(t2_path)
t2_data = t2_nii.get_fdata()

# Tumor mask (all tumor labels: 1=necrotic, 2=edema, 4=enhancing)
tumor_mask = (gt_data > 0)
print(f"Tumor voxels: {np.sum(tumor_mask)}")

# Identify ventricles using T2 intensity thresholding
# Ventricles are bright on T2 (CSF is hyperintense)
# Focus on central brain region where lateral ventricles are located

# Get brain center
nx, ny, nz = t2_data.shape
center_x, center_y, center_z = nx // 2, ny // 2, nz // 2

# Create a central brain mask (where ventricles should be)
# Ventricles are in the central region of the brain
central_mask = np.zeros_like(t2_data, dtype=bool)
x_range = slice(int(nx * 0.25), int(nx * 0.75))
y_range = slice(int(ny * 0.25), int(ny * 0.75))
z_range = slice(int(nz * 0.3), int(nz * 0.7))
central_mask[x_range, y_range, z_range] = True

# Threshold T2 for CSF (ventricles) - high intensity
# Use a high percentile threshold within central region
central_t2 = t2_data[central_mask]
t2_threshold = np.percentile(central_t2[central_t2 > 0], 92)  # Top ~8% intensity

# Ventricle mask: high T2 signal in central brain, not in tumor
ventricle_mask = (t2_data > t2_threshold) & central_mask & ~tumor_mask

# Clean up ventricle mask with morphological operations
ventricle_mask = binary_erosion(ventricle_mask, iterations=1)
ventricle_mask = binary_dilation(ventricle_mask, iterations=1)

print(f"Ventricle voxels: {np.sum(ventricle_mask)}")

# Compute minimum distance from tumor to ventricle
if np.sum(tumor_mask) > 0 and np.sum(ventricle_mask) > 0:
    # Distance transform from ventricle surface
    # Compute distance from each voxel to nearest ventricle voxel
    ventricle_dt = distance_transform_edt(~ventricle_mask, sampling=voxel_dims)
    
    # Get tumor surface (boundary voxels)
    tumor_eroded = binary_erosion(tumor_mask, iterations=1)
    tumor_surface = tumor_mask & ~tumor_eroded
    
    # Minimum distance from tumor surface to ventricle
    tumor_surface_distances = ventricle_dt[tumor_surface]
    min_distance = float(np.min(tumor_surface_distances))
    
    # Find location of minimum distance point
    min_idx = np.argmin(ventricle_dt[tumor_mask])
    tumor_coords = np.array(np.where(tumor_mask)).T
    closest_tumor_voxel = tumor_coords[min_idx]
    
    # Convert to RAS coordinates
    closest_point_ras = nib.affines.apply_affine(affine, closest_tumor_voxel)
    
    # Determine which ventricle component is nearest based on z-coordinate
    z_frac = closest_tumor_voxel[2] / nz
    if z_frac > 0.6:
        nearest_component = "frontal horn"
    elif z_frac > 0.45:
        nearest_component = "body"
    elif z_frac > 0.35:
        nearest_component = "atrium"
    else:
        nearest_component = "temporal horn"
    
    # Check for invasion (distance ~ 0)
    invasion_suspected = min_distance < 2.0  # Less than 2mm suggests contact
    
    # Classification
    if min_distance < 1.0:
        classification = "Contact"
    elif min_distance <= 5.0:
        classification = "Adjacent"
    elif min_distance <= 10.0:
        classification = "Close"
    else:
        classification = "Distant"
    
else:
    min_distance = -1.0
    classification = "Unknown"
    nearest_component = "unknown"
    invasion_suspected = False
    closest_point_ras = [0, 0, 0]

print(f"Minimum tumor-ventricle distance: {min_distance:.2f} mm")
print(f"Classification: {classification}")
print(f"Nearest ventricle component: {nearest_component}")
print(f"Invasion suspected: {invasion_suspected}")

# Save ground truth
gt_result = {
    "sample_id": sample_id,
    "min_distance_mm": round(min_distance, 2),
    "classification": classification,
    "nearest_ventricle_component": nearest_component,
    "ventricular_invasion_suspected": invasion_suspected,
    "closest_point_ras": [round(x, 2) for x in closest_point_ras.tolist()],
    "tumor_voxels": int(np.sum(tumor_mask)),
    "ventricle_voxels": int(np.sum(ventricle_mask)),
    "voxel_dims_mm": [round(x, 3) for x in voxel_dims]
}

gt_path = "/tmp/proximity_ground_truth.json"
with open(gt_path, "w") as f:
    json.dump(gt_result, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

export SAMPLE_ID SAMPLE_DIR GROUND_TRUTH_DIR

# Create Slicer Python script to load all MRI volumes
cat > /tmp/load_brats_proximity.py << PYEOF
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

print("Loading BraTS MRI volumes for proximity assessment...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up views - start with FLAIR (good for tumor + ventricle visualization)
if loaded_nodes:
    flair_node = slicer.util.getNode("FLAIR")
    t2_node = slicer.util.getNode("T2")
    
    # Set FLAIR as background
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID() if flair_node else loaded_nodes[0].GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Center on the middle of the data
    ref_node = flair_node if flair_node else loaded_nodes[0]
    bounds = [0]*6
    ref_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

print("Setup complete - ready for proximity assessment task")
print("")
print("TIPS:")
print("  - Tumor appears bright on FLAIR (edema) and T1_Contrast (enhancing core)")
print("  - Ventricles appear bright on T2, dark on FLAIR (CSF is suppressed)")
print("  - Use Window/Level to optimize visualization")
print("  - Use Markups -> Line tool for distance measurement")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the loading script
echo "Launching 3D Slicer with BraTS MRI volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_proximity.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volumes to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/proximity_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tumor-to-Ventricle Proximity Assessment"
echo "=============================================="
echo ""
echo "A brain MRI is loaded with four sequences: FLAIR, T1, T1_Contrast, T2"
echo ""
echo "Your goal:"
echo "  1. Identify the tumor (bright on FLAIR for edema, T1ce for enhancement)"
echo "  2. Identify the lateral ventricles (CSF-filled spaces, bright on T2)"
echo "  3. Find the point where tumor and ventricle are closest"
echo "  4. Measure the minimum distance using Markups ruler tool"
echo "  5. Classify: Contact (0mm), Adjacent (1-5mm), Close (5-10mm), Distant (>10mm)"
echo "  6. Note which ventricle component is nearest"
echo ""
echo "Save outputs:"
echo "  - Measurement: ~/Documents/SlicerData/BraTS/ventricle_distance.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/proximity_report.json"
echo ""