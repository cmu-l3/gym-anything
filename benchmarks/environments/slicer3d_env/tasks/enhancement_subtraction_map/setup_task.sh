#!/bin/bash
echo "=== Setting up Enhancement Subtraction Map Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

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

# Verify required files exist (T1 and T1ce are essential for this task)
REQUIRED_FILES=(
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
)

echo "Verifying MRI volumes for subtraction task..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth exists (segmentation with label 4 = enhancing tumor)
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Clean up any previous outputs
rm -f /tmp/enhancement_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/enhancement_map.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/enhancement_mask.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/enhancement_report.txt" 2>/dev/null || true

# Pre-compute ground truth subtraction (T1ce - T1) for verification
echo "Pre-computing ground truth subtraction..."
python3 << PYEOF
import numpy as np
import nibabel as nib
import json
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"

# Load T1 and T1ce
t1_path = os.path.join(sample_dir, f"{sample_id}_t1.nii.gz")
t1ce_path = os.path.join(sample_dir, f"{sample_id}_t1ce.nii.gz")

print(f"Loading T1: {t1_path}")
t1_nii = nib.load(t1_path)
t1_data = t1_nii.get_fdata().astype(np.float32)

print(f"Loading T1ce: {t1ce_path}")
t1ce_nii = nib.load(t1ce_path)
t1ce_data = t1ce_nii.get_fdata().astype(np.float32)

# Compute ground truth subtraction
print("Computing ground truth subtraction (T1ce - T1)...")
gt_subtraction = t1ce_data - t1_data

# Save ground truth subtraction
gt_sub_path = os.path.join(gt_dir, f"{sample_id}_subtraction_gt.nii.gz")
gt_sub_nii = nib.Nifti1Image(gt_subtraction, t1_nii.affine, t1_nii.header)
nib.save(gt_sub_nii, gt_sub_path)
print(f"Saved ground truth subtraction to {gt_sub_path}")

# Load ground truth segmentation to get enhancing tumor region
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
gt_seg_nii = nib.load(gt_seg_path)
gt_seg_data = gt_seg_nii.get_fdata().astype(np.int32)

# Enhancing tumor is label 4 in BraTS
enhancing_mask = (gt_seg_data == 4)
enhancing_voxels = np.sum(enhancing_mask)

# Calculate ground truth enhancement metrics
voxel_dims = t1_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

# Create thresholded enhancement mask (as reference)
threshold = 100
gt_enhancement_mask = (gt_subtraction > threshold)

# Metrics in the enhancing region
if np.any(gt_enhancement_mask):
    max_enhancement = float(np.max(gt_subtraction[gt_enhancement_mask]))
    mean_enhancement = float(np.mean(gt_subtraction[gt_enhancement_mask]))
    enhancement_volume_ml = float(np.sum(gt_enhancement_mask) * voxel_volume_ml)
else:
    max_enhancement = float(np.max(gt_subtraction)) if np.any(gt_subtraction > 0) else 0.0
    mean_enhancement = 0.0
    enhancement_volume_ml = 0.0

# Save metrics for verification
gt_metrics = {
    "sample_id": sample_id,
    "t1_shape": list(t1_data.shape),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_ml": float(voxel_volume_ml),
    "subtraction_min": float(np.min(gt_subtraction)),
    "subtraction_max": float(np.max(gt_subtraction)),
    "subtraction_mean": float(np.mean(gt_subtraction)),
    "threshold_used": threshold,
    "enhancement_volume_ml": enhancement_volume_ml,
    "max_enhancement_intensity": max_enhancement,
    "mean_enhancement_intensity": mean_enhancement,
    "enhancing_tumor_voxels_gt": int(enhancing_voxels),
    "enhancing_tumor_volume_ml_gt": float(enhancing_voxels * voxel_volume_ml),
    "thresholded_voxels": int(np.sum(gt_enhancement_mask)),
}

gt_metrics_path = os.path.join(gt_dir, f"{sample_id}_enhancement_gt.json")
with open(gt_metrics_path, "w") as f:
    json.dump(gt_metrics, f, indent=2)
print(f"Saved ground truth metrics to {gt_metrics_path}")

print(f"\nGround truth enhancement metrics:")
print(f"  Max enhancement: {max_enhancement:.1f}")
print(f"  Mean enhancement: {mean_enhancement:.1f}")
print(f"  Enhancement volume: {enhancement_volume_ml:.2f} mL")
print(f"  GT enhancing tumor volume: {enhancing_voxels * voxel_volume_ml:.2f} mL")
PYEOF

# Create a Slicer Python script to load the T1 and T1ce volumes
cat > /tmp/load_subtraction_volumes.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Load only T1 and T1ce for this task (plus FLAIR for context)
volumes = [
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
]

print("Loading MRI volumes for enhancement subtraction task...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name} from {filepath}")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")
        else:
            print(f"    ERROR loading {filepath}")
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up the views - show T1_Contrast by default (where enhancement is visible)
if loaded_nodes:
    t1ce_node = slicer.util.getNode("T1_Contrast")
    if not t1ce_node:
        t1ce_node = loaded_nodes[0]

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(t1ce_node.GetID())

    # Reset views
    slicer.util.resetSliceViews()

    # Center on the data
    bounds = [0]*6
    t1ce_node.GetBounds(bounds)
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

print("Setup complete - ready for enhancement subtraction task")
print("")
print("Available volumes:")
print("  - T1: Pre-contrast T1-weighted MRI")
print("  - T1_Contrast: Post-contrast (gadolinium) T1-weighted MRI")
print("  - FLAIR: For anatomical reference")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with T1 and T1ce volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_subtraction_volumes.py > /tmp/slicer_launch.log 2>&1 &

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

# Wait for volumes to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/enhancement_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Enhancement Map Creation via Subtraction"
echo "==============================================="
echo ""
echo "You have brain MRI volumes loaded:"
echo "  - T1: Pre-contrast T1-weighted MRI"
echo "  - T1_Contrast: Post-contrast (gadolinium-enhanced) T1-weighted MRI"
echo ""
echo "Your goal:"
echo "  1. Create a subtraction image: T1_Contrast - T1"
echo "     (Use Volume Calculator, Simple Filters > Subtract, or Python)"
echo "  2. Threshold the subtraction to isolate enhancement (threshold >= 100)"
echo "  3. Create a binary mask of enhancing regions"
echo ""
echo "Save your outputs:"
echo "  - Enhancement map: ~/Documents/SlicerData/BraTS/enhancement_map.nii.gz"
echo "  - Enhancement mask: ~/Documents/SlicerData/BraTS/enhancement_mask.nii.gz"
echo "  - Report: ~/Documents/SlicerData/BraTS/enhancement_report.txt"
echo "    (Include: volume in mL, max intensity, mean intensity)"
echo ""