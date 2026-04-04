#!/bin/bash
echo "=== Setting up Tumor Infiltration Pattern Assessment Task ==="

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

# Compute infiltration ground truth metrics
echo "Computing infiltration ground truth metrics..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
    from scipy import ndimage
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
    import nibabel as nib
    from scipy import ndimage

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"

gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
enhancing_mask = (gt_data == 4)
tumor_core_mask = (gt_data == 1) | (gt_data == 4)
whole_tumor_mask = (gt_data > 0)
edema_infiltration_mask = (gt_data == 2)

# Compute volumes
voxel_vol_mm3 = float(np.prod(voxel_dims))
enhancing_vol = np.sum(enhancing_mask) * voxel_vol_mm3
tumor_core_vol = np.sum(tumor_core_mask) * voxel_vol_mm3
whole_tumor_vol = np.sum(whole_tumor_mask) * voxel_vol_mm3
edema_vol = np.sum(edema_infiltration_mask) * voxel_vol_mm3

# Infiltration index = whole tumor / enhancing (or tumor core if enhancing is too small)
if enhancing_vol > 0:
    infiltration_index = whole_tumor_vol / enhancing_vol
else:
    infiltration_index = whole_tumor_vol / max(tumor_core_vol, 1.0)

# Compute infiltration radius using distance transform
# Max distance from enhancing boundary to FLAIR boundary
max_infiltration_radius = 0.0

if np.any(enhancing_mask) and np.any(edema_infiltration_mask):
    # Distance from every voxel to nearest enhancing voxel
    enhancing_dt = ndimage.distance_transform_edt(~enhancing_mask, sampling=voxel_dims)
    
    # Max distance within the edema/infiltration zone
    edema_distances = enhancing_dt[edema_infiltration_mask]
    if len(edema_distances) > 0:
        max_infiltration_radius = float(np.max(edema_distances))
        percentile_95_radius = float(np.percentile(edema_distances, 95))
elif np.any(whole_tumor_mask) and np.any(tumor_core_mask):
    # Fallback: distance from core to whole tumor boundary
    core_dt = ndimage.distance_transform_edt(~tumor_core_mask, sampling=voxel_dims)
    non_core_tumor = whole_tumor_mask & ~tumor_core_mask
    if np.any(non_core_tumor):
        max_infiltration_radius = float(np.max(core_dt[non_core_tumor]))

# Determine border characterization based on gradient analysis
# Sharp if most of tumor boundary has clear demarcation, infiltrative otherwise
if infiltration_index < 2.0:
    border_char = "sharp"
elif infiltration_index < 4.0:
    border_char = "intermediate"
else:
    border_char = "infiltrative"

# Determine infiltration grade
if infiltration_index < 1.5 and max_infiltration_radius < 10:
    expected_grade = 1
elif infiltration_index < 3.0 and max_infiltration_radius < 20:
    expected_grade = 2
elif infiltration_index < 6.0:
    expected_grade = 3
else:
    expected_grade = 4

# Identify infiltrated structures based on tumor location
# This is a simplified heuristic based on tumor centroid and extent
infiltrated_structures = []

# Get tumor centroid and bounds
tumor_coords = np.where(whole_tumor_mask)
if len(tumor_coords[0]) > 0:
    centroid = [float(np.mean(c)) for c in tumor_coords]
    bounds_min = [float(np.min(c)) for c in tumor_coords]
    bounds_max = [float(np.max(c)) for c in tumor_coords]
    
    # Check for midline crossing (corpus callosum involvement)
    mid_sagittal = gt_data.shape[0] // 2
    left_tumor = np.any(whole_tumor_mask[:mid_sagittal-5, :, :])
    right_tumor = np.any(whole_tumor_mask[mid_sagittal+5:, :, :])
    if left_tumor and right_tumor:
        infiltrated_structures.append("corpus_callosum")
    
    # Deep structures based on position (simplified)
    # Corona radiata - superior white matter
    if centroid[2] > gt_data.shape[2] * 0.5:
        infiltrated_structures.append("corona_radiata")
    
    # Cortex - if tumor extends to brain surface
    margin = 10  # voxels from edge
    if bounds_min[0] < margin or bounds_max[0] > gt_data.shape[0] - margin:
        infiltrated_structures.append("cortex")
    if bounds_min[1] < margin or bounds_max[1] > gt_data.shape[1] - margin:
        infiltrated_structures.append("cortex")

# Surgical margin recommendation based on infiltration
if expected_grade == 1:
    margin_mm = 5
    resectability = "gross total"
elif expected_grade == 2:
    margin_mm = 10
    resectability = "gross total"
elif expected_grade == 3:
    margin_mm = 15
    resectability = "subtotal"
else:
    margin_mm = 20
    resectability = "biopsy only"

# Remove duplicates from structures
infiltrated_structures = list(set(infiltrated_structures))

# Save ground truth
gt_metrics = {
    "sample_id": sample_id,
    "infiltration_index": round(infiltration_index, 2),
    "max_infiltration_radius_mm": round(max_infiltration_radius, 1),
    "border_characterization": border_char,
    "expected_infiltration_grade": expected_grade,
    "infiltrated_structures": infiltrated_structures,
    "expected_margin_mm": margin_mm,
    "expected_resectability": resectability,
    "volumes_mm3": {
        "enhancing": round(enhancing_vol, 1),
        "tumor_core": round(tumor_core_vol, 1),
        "whole_tumor": round(whole_tumor_vol, 1),
        "edema_infiltration": round(edema_vol, 1)
    },
    "voxel_dims_mm": [float(v) for v in voxel_dims]
}

gt_output_path = os.path.join(gt_dir, f"{sample_id}_infiltration_gt.json")
with open(gt_output_path, "w") as f:
    json.dump(gt_metrics, f, indent=2)

print(f"Ground truth saved to: {gt_output_path}")
print(f"  Infiltration index: {infiltration_index:.2f}")
print(f"  Max infiltration radius: {max_infiltration_radius:.1f} mm")
print(f"  Border characterization: {border_char}")
print(f"  Expected grade: {expected_grade}")
print(f"  Infiltrated structures: {infiltrated_structures}")
PYEOF

# Record initial state
rm -f /tmp/infiltration_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/infiltration_markups.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/infiltration_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Create a Slicer Python script to load all volumes
cat > /tmp/load_infiltration_volumes.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Define volumes to load with display names
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("Loading BraTS MRI volumes for infiltration assessment...")
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

# Set up views for infiltration assessment
# Use FLAIR as primary (shows full extent) with T1ce available for comparison
if loaded_nodes:
    flair_node = slicer.util.getNode("FLAIR") if slicer.util.getNode("FLAIR") else loaded_nodes[0]
    
    # Set FLAIR as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    bounds = [0]*6
    flair_node.GetBounds(bounds)
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

print("Setup complete - ready for infiltration pattern assessment")
print("")
print("TIPS for infiltration assessment:")
print("  - Compare FLAIR (edema/infiltration) with T1_Contrast (enhancing core)")
print("  - Use the ruler tool to measure from enhancing edge to FLAIR edge")
print("  - Place at least 3 measurements around the tumor")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_infiltration_volumes.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Maximize window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volumes to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/infiltration_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tumor Infiltration Pattern Assessment"
echo "============================================"
echo ""
echo "Analyze the tumor's infiltration pattern by:"
echo "  1. Comparing T1_Contrast (enhancing) with FLAIR (full extent)"
echo "  2. Characterizing the tumor border (sharp/intermediate/infiltrative)"
echo "  3. Identifying infiltrated anatomical structures"
echo "  4. Measuring infiltration radius (enhancing edge to FLAIR edge)"
echo "  5. Calculating infiltration index (FLAIR vol / T1ce vol)"
echo "  6. Assigning infiltration grade (I-IV)"
echo ""
echo "Save outputs to:"
echo "  - Markups: ~/Documents/SlicerData/BraTS/infiltration_markups.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/infiltration_report.json"
echo ""