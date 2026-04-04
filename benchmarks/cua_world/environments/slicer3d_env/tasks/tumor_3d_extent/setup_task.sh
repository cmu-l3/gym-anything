#!/bin/bash
echo "=== Setting up Three-Dimensional Tumor Extent Measurement Task ==="

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

# Verify required MRI sequences exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth segmentation exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Calculate ground truth dimensions from segmentation bounding box
echo "Computing ground truth tumor dimensions..."
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

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"

# Load ground truth segmentation
gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
seg_nii = nib.load(gt_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel spacing (mm): {voxel_dims}")

# Create tumor mask (all non-zero labels: 1=necrotic, 2=edema, 4=enhancing)
tumor_mask = (seg_data > 0)

if not np.any(tumor_mask):
    print("ERROR: No tumor found in segmentation!")
    sys.exit(1)

# Find bounding box coordinates
coords = np.where(tumor_mask)
x_min, x_max = coords[0].min(), coords[0].max()
y_min, y_max = coords[1].min(), coords[1].max()
z_min, z_max = coords[2].min(), coords[2].max()

# Calculate dimensions in mm
# In typical MRI orientation:
# - X axis: Left-Right (Mediolateral)
# - Y axis: Anterior-Posterior
# - Z axis: Superior-Inferior
ml_extent_voxels = x_max - x_min + 1
ap_extent_voxels = y_max - y_min + 1
si_extent_voxels = z_max - z_min + 1

ml_extent_mm = ml_extent_voxels * voxel_dims[0]
ap_extent_mm = ap_extent_voxels * voxel_dims[1]
si_extent_mm = si_extent_voxels * voxel_dims[2]

# Calculate ellipsoid volume
ellipsoid_volume_mm3 = (np.pi / 6.0) * ml_extent_mm * ap_extent_mm * si_extent_mm
ellipsoid_volume_ml = ellipsoid_volume_mm3 / 1000.0

# Also calculate actual tumor volume for reference
actual_volume_mm3 = np.sum(tumor_mask) * np.prod(voxel_dims)
actual_volume_ml = actual_volume_mm3 / 1000.0

# Calculate bounding box center in world coordinates
center_voxel = [
    (x_min + x_max) / 2.0,
    (y_min + y_max) / 2.0,
    (z_min + z_max) / 2.0
]
center_mm = [
    center_voxel[0] * voxel_dims[0],
    center_voxel[1] * voxel_dims[1],
    center_voxel[2] * voxel_dims[2]
]

gt_data = {
    "sample_id": sample_id,
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "bounding_box_voxels": {
        "x_min": int(x_min), "x_max": int(x_max),
        "y_min": int(y_min), "y_max": int(y_max),
        "z_min": int(z_min), "z_max": int(z_max)
    },
    "dimensions_mm": {
        "AP": float(round(ap_extent_mm, 2)),
        "ML": float(round(ml_extent_mm, 2)),
        "SI": float(round(si_extent_mm, 2))
    },
    "ellipsoid_volume_ml": float(round(ellipsoid_volume_ml, 2)),
    "actual_tumor_volume_ml": float(round(actual_volume_ml, 2)),
    "tumor_center_mm": [float(round(c, 2)) for c in center_mm]
}

# Save ground truth
gt_output_path = os.path.join(gt_dir, f"{sample_id}_dimensions_gt.json")
with open(gt_output_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth dimensions:")
print(f"  AP (Anterior-Posterior): {ap_extent_mm:.1f} mm")
print(f"  ML (Mediolateral): {ml_extent_mm:.1f} mm")
print(f"  SI (Superior-Inferior): {si_extent_mm:.1f} mm")
print(f"  Ellipsoid volume: {ellipsoid_volume_ml:.2f} mL")
print(f"  Actual tumor volume: {actual_volume_ml:.2f} mL")
print(f"\nGround truth saved to: {gt_output_path}")
PYEOF

# Clean up any previous task outputs
rm -f "$BRATS_DIR/tumor_dimensions.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_extent_report.json" 2>/dev/null || true
rm -f /tmp/tumor_extent_result.json 2>/dev/null || true

# Create Slicer Python script to load the MRI volumes
cat > /tmp/load_tumor_mri.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Load FLAIR (shows edema well) and T1-contrast (shows enhancing tumor)
volumes_to_load = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
]

print("Loading brain MRI volumes for tumor measurement...")
loaded_nodes = []

for filename, display_name in volumes_to_load:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")

print(f"\nLoaded {len(loaded_nodes)} volumes")

if loaded_nodes:
    # Set FLAIR as background (good for seeing full tumor extent with edema)
    flair_node = slicer.util.getNode("FLAIR")
    
    # Configure slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    # Reset and center views on the data
    slicer.util.resetSliceViews()
    
    # Get tumor approximate center and navigate there
    bounds = [0]*6
    flair_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set slice offsets to center of volume
    layoutManager = slicer.app.layoutManager()
    layoutManager.sliceWidget("Red").sliceLogic().GetSliceNode().SetSliceOffset(center[2])
    layoutManager.sliceWidget("Green").sliceLogic().GetSliceNode().SetSliceOffset(center[1])
    layoutManager.sliceWidget("Yellow").sliceLogic().GetSliceNode().SetSliceOffset(center[0])
    
    # Set conventional layout for multi-planar viewing
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

print("\nSetup complete - ready for tumor extent measurement")
print("\nINSTRUCTIONS:")
print("1. Use axial view (Red) to measure AP and ML diameters")
print("2. Use sagittal view (Yellow) to measure SI diameter")
print("3. Create ruler markups named: Tumor_AP_mm, Tumor_ML_mm, Tumor_SI_mm")
print("4. Save markups and create a JSON report with measurements")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the setup script
echo "Launching 3D Slicer with brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_tumor_mri.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
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

sleep 5

# Take initial screenshot
take_screenshot /tmp/tumor_extent_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Three-Dimensional Tumor Extent Measurement"
echo "================================================="
echo ""
echo "Measure the brain tumor's maximum extent in three planes:"
echo ""
echo "1. AP (Anteroposterior): Front-to-back diameter in axial view"
echo "2. ML (Mediolateral): Left-to-right diameter in axial view"  
echo "3. SI (Superoinferior): Top-to-bottom diameter in sagittal view"
echo ""
echo "Create rulers named: Tumor_AP_mm, Tumor_ML_mm, Tumor_SI_mm"
echo ""
echo "Calculate ellipsoid volume: V = (π/6) × AP × ML × SI"
echo ""
echo "Save outputs to:"
echo "  - Markups: ~/Documents/SlicerData/BraTS/tumor_dimensions.mrk.json"
echo "  - Report:  ~/Documents/SlicerData/BraTS/tumor_extent_report.json"
echo ""