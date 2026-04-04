#!/bin/bash
echo "=== Setting up Brain Tumor Mass Effect Grading Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOTS_DIR="$BRATS_DIR/screenshots"

# Create required directories
mkdir -p "$BRATS_DIR"
mkdir -p "$SCREENSHOTS_DIR"
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

# Verify ground truth segmentation exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth segmentation verified"

# Calculate ground truth mass effect metrics from tumor segmentation
echo "Calculating ground truth mass effect metrics..."
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
gt_seg_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
flair_path = "$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"
gt_output_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_mass_effect_gt.json"

# Load segmentation and FLAIR
seg_nii = nib.load(gt_seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
flair_nii = nib.load(flair_path)
flair_data = flair_nii.get_fdata()

voxel_dims = seg_nii.header.get_zooms()[:3]
print(f"Volume shape: {seg_data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Total tumor = labels 1, 2, 4
tumor_mask = (seg_data > 0)
tumor_voxels = np.sum(tumor_mask)
print(f"Total tumor voxels: {tumor_voxels}")

# Find tumor center of mass
if tumor_voxels > 0:
    tumor_coords = np.argwhere(tumor_mask)
    tumor_centroid = tumor_coords.mean(axis=0)
    print(f"Tumor centroid (voxels): {tumor_centroid}")
else:
    tumor_centroid = np.array(seg_data.shape) / 2
    print("Warning: No tumor found, using image center")

# Calculate expected midline shift
# Brain midline should be at center of x-axis (assuming standard orientation)
image_center_x = seg_data.shape[0] / 2
tumor_center_x = tumor_centroid[0]

# Estimate midline shift based on tumor position and size
# Large tumors on one side push midline away
tumor_extent_x = 0
if tumor_voxels > 0:
    x_coords = np.where(np.any(tumor_mask, axis=(1, 2)))[0]
    if len(x_coords) > 0:
        tumor_extent_x = (x_coords.max() - x_coords.min()) * voxel_dims[0]

# Simplified midline shift estimate (tumor pushes midline proportionally)
# More sophisticated calculation would need actual brain segmentation
tumor_volume_ml = tumor_voxels * np.prod(voxel_dims) / 1000.0
relative_position = (tumor_center_x - image_center_x) / (seg_data.shape[0] / 2)

# Estimate midline shift based on tumor size and position
# Larger tumors cause more shift; tumor side determines direction
if tumor_volume_ml > 50:
    expected_midline_shift = min(15.0, tumor_volume_ml / 5.0) * abs(relative_position)
elif tumor_volume_ml > 20:
    expected_midline_shift = min(10.0, tumor_volume_ml / 4.0) * abs(relative_position)
elif tumor_volume_ml > 5:
    expected_midline_shift = min(5.0, tumor_volume_ml / 3.0) * abs(relative_position)
else:
    expected_midline_shift = max(0, tumor_volume_ml / 2.0) * abs(relative_position)

print(f"Tumor volume: {tumor_volume_ml:.1f} mL")
print(f"Expected midline shift: {expected_midline_shift:.1f} mm")

# Estimate ventricular compression
# If tumor is large and near ventricles, expect compression
# Tumor side ventricle will be compressed
tumor_side = "left" if tumor_center_x < image_center_x else "right"
ventricular_ratio_expected = 1.0  # Normal ratio

if tumor_volume_ml > 30:
    ventricular_ratio_expected = max(0.3, 1.0 - tumor_volume_ml / 100.0)
elif tumor_volume_ml > 10:
    ventricular_ratio_expected = max(0.5, 1.0 - tumor_volume_ml / 60.0)

print(f"Tumor side: {tumor_side}")
print(f"Expected ventricular ratio: {ventricular_ratio_expected:.2f}")

# Estimate herniation risk
subfalcine_expected = "Present" if expected_midline_shift > 5.0 else "Absent"
uncal_expected = "Absent"  # Requires temporal lobe tumor to cause uncal herniation

# Check if tumor is in temporal region (would suggest uncal herniation risk)
if tumor_voxels > 0:
    z_coords = np.where(np.any(tumor_mask, axis=(0, 1)))[0]
    z_fraction = np.mean(z_coords) / seg_data.shape[2] if len(z_coords) > 0 else 0.5
    # Lower z values = more inferior = temporal region
    if z_fraction < 0.4 and tumor_volume_ml > 20:
        uncal_expected = "Present"

# Estimate sulcal effacement
if tumor_volume_ml > 40:
    sulcal_effacement_expected = 2
elif tumor_volume_ml > 15:
    sulcal_effacement_expected = 1
else:
    sulcal_effacement_expected = 0

print(f"Expected subfalcine herniation: {subfalcine_expected}")
print(f"Expected uncal herniation: {uncal_expected}")
print(f"Expected sulcal effacement: {sulcal_effacement_expected}")

# Determine overall grade
if expected_midline_shift > 10.0 or subfalcine_expected == "Present" or uncal_expected == "Present":
    expected_grade = "Severe"
elif expected_midline_shift > 5.0 or ventricular_ratio_expected < 0.5 or sulcal_effacement_expected == 2:
    expected_grade = "Moderate"
else:
    expected_grade = "Mild"

print(f"Expected overall grade: {expected_grade}")

# Save ground truth
gt_data = {
    "sample_id": sample_id,
    "tumor_volume_ml": round(tumor_volume_ml, 2),
    "tumor_side": tumor_side,
    "expected_midline_shift_mm": round(expected_midline_shift, 1),
    "expected_ventricular_ratio": round(ventricular_ratio_expected, 2),
    "expected_subfalcine_herniation": subfalcine_expected,
    "expected_uncal_herniation": uncal_expected,
    "expected_sulcal_effacement": sulcal_effacement_expected,
    "expected_overall_grade": expected_grade,
    "tumor_centroid_voxel": [round(c, 1) for c in tumor_centroid.tolist()],
    "image_dimensions": list(seg_data.shape),
    "voxel_dimensions_mm": [round(v, 3) for v in voxel_dims]
}

with open(gt_output_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to: {gt_output_path}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_mass_effect_gt.json" ]; then
    echo "ERROR: Failed to create ground truth metrics!"
    exit 1
fi
echo "Ground truth metrics calculated"

# Record initial state
rm -f /tmp/mass_effect_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/mass_effect_measurements.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/mass_effect_report.json" 2>/dev/null || true
rm -rf "$SCREENSHOTS_DIR"/* 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Create a Slicer Python script to load all volumes
cat > /tmp/load_mass_effect_volumes.py << PYEOF
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

print("Loading BraTS MRI volumes for mass effect assessment...")
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

# Set up views for mass effect assessment
if loaded_nodes:
    # Use T1 for midline assessment (better gray/white differentiation)
    t1_node = slicer.util.getNode("T1") if slicer.util.getNode("T1") else loaded_nodes[0]
    flair_node = slicer.util.getNode("FLAIR") if slicer.util.getNode("FLAIR") else loaded_nodes[0]
    
    # Set T1 as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(t1_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to approximate level of lateral ventricles (middle of brain)
    bounds = [0]*6
    t1_node.GetBounds(bounds)
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        if color == "Red":  # Axial view
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal view
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal view
            sliceNode.SetSliceOffset(center[0])

print("Setup complete - ready for mass effect assessment task")
print("")
print("TIP: Use axial view (Red) to measure midline shift and ventricular widths")
print("TIP: Switch between T1 and FLAIR to assess different structures")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_mass_effect_volumes.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Dismiss startup dialogs
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
take_screenshot /tmp/mass_effect_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Tumor Mass Effect Grading"
echo "======================================="
echo ""
echo "Assess mass effect by measuring:"
echo "  1. Midline shift (mm) at septum pellucidum level"
echo "  2. Ventricular compression (ipsilateral/contralateral ratio)"
echo "  3. Subfalcine herniation (Present/Absent, extent if present)"
echo "  4. Sulcal effacement score (0/1/2)"
echo "  5. Uncal herniation (Present/Absent)"
echo "  6. Overall grade (Mild/Moderate/Severe)"
echo ""
echo "Save to:"
echo "  - Measurements: ~/Documents/SlicerData/BraTS/mass_effect_measurements.mrk.json"
echo "  - Screenshots: ~/Documents/SlicerData/BraTS/screenshots/"
echo "  - Report: ~/Documents/SlicerData/BraTS/mass_effect_report.json"
echo ""