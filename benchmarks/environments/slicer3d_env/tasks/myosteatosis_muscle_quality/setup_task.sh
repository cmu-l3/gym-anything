#!/bin/bash
echo "=== Setting up Myosteatosis Muscle Quality Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data or generates synthetic with realistic HU)
echo "Preparing AMOS 2022 abdominal CT data..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Randomly assign patient sex (for this task)
PATIENT_SEX=$(python3 -c "import random; random.seed(42); print(random.choice(['Male', 'Female']))")
echo "Assigned patient sex: $PATIENT_SEX"

# Save patient info for agent to read
mkdir -p "$AMOS_DIR"
cat > "$AMOS_DIR/patient_info.txt" << EOF
Patient Information
===================
Case ID: $CASE_ID
Sex: $PATIENT_SEX
Study: Abdominal CT
Task: Muscle Quality Assessment (Myosteatosis)
EOF
chmod 644 "$AMOS_DIR/patient_info.txt"

# Create ground truth muscle segmentation and measurements
echo "Generating ground truth muscle segmentation at L3..."
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
    from scipy.ndimage import label as scipy_label, binary_erosion, binary_dilation
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import label as scipy_label, binary_erosion, binary_dilation

ct_path = "$CT_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
case_id = "$CASE_ID"
patient_sex = "$PATIENT_SEX"

print(f"Loading CT volume: {ct_path}")
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}")
print(f"Voxel spacing: {spacing}")

nx, ny, nz = ct_data.shape

# Find L3 level - approximately middle of abdominal volume
# In typical abdominal CT, L3 is roughly in the middle third
l3_slice = int(nz * 0.45)  # Approximate L3 level
print(f"L3 slice index: {l3_slice}")

# Create muscle mask at L3 using HU thresholding
# Skeletal muscle: -29 to +150 HU, typically 30-50 HU for healthy muscle
muscle_hu_min = -29
muscle_hu_max = 150

# Get the L3 slice
l3_data = ct_data[:, :, l3_slice]

# Threshold for muscle HU range
muscle_mask_2d = (l3_data >= muscle_hu_min) & (l3_data <= muscle_hu_max)

# Focus on posterior abdominal wall (back half of image, where psoas/paraspinal are)
center_y = ny // 2
posterior_region = np.zeros_like(muscle_mask_2d)
posterior_region[:, center_y:] = True  # Posterior half

# Also exclude very anterior regions where bowel might be
anterior_cutoff = int(ny * 0.3)
posterior_region[:, :anterior_cutoff] = False

# Apply posterior constraint
muscle_mask_2d = muscle_mask_2d & posterior_region

# Exclude regions that are clearly bone (very high HU near spine)
# But keep muscle adjacent to spine
bone_mask = (l3_data > 200)
# Don't remove muscle just because it's near bone

# Clean up - remove small components
labeled, n_features = scipy_label(muscle_mask_2d)
if n_features > 0:
    component_sizes = [(labeled == i).sum() for i in range(1, n_features + 1)]
    # Keep only larger components (psoas and paraspinal are substantial)
    min_component_size = 100  # voxels
    for i, size in enumerate(component_sizes, 1):
        if size < min_component_size:
            muscle_mask_2d[labeled == i] = False

# Create 3D muscle mask (single slice for L3 assessment)
muscle_mask_3d = np.zeros(ct_data.shape, dtype=np.int16)
muscle_mask_3d[:, :, l3_slice] = muscle_mask_2d.astype(np.int16)

# Also include adjacent slices for a small range around L3 (±2 slices)
for offset in [-2, -1, 1, 2]:
    if 0 <= l3_slice + offset < nz:
        slice_data = ct_data[:, :, l3_slice + offset]
        slice_mask = (slice_data >= muscle_hu_min) & (slice_data <= muscle_hu_max) & posterior_region
        muscle_mask_3d[:, :, l3_slice + offset] = slice_mask.astype(np.int16)

# Calculate ground truth metrics
muscle_voxels = muscle_mask_3d[:, :, l3_slice] > 0
muscle_area_mm2 = np.sum(muscle_voxels) * spacing[0] * spacing[1]
muscle_area_cm2 = muscle_area_mm2 / 100.0  # Convert to cm²

# Extract HU values from muscle region
muscle_hu_values = l3_data[muscle_mask_2d]
mean_hu = float(np.mean(muscle_hu_values)) if len(muscle_hu_values) > 0 else 0.0
std_hu = float(np.std(muscle_hu_values)) if len(muscle_hu_values) > 0 else 0.0
median_hu = float(np.median(muscle_hu_values)) if len(muscle_hu_values) > 0 else 0.0

# Determine myosteatosis based on sex-specific thresholds
threshold = 41 if patient_sex == "Male" else 33
myosteatosis_present = mean_hu <= threshold

# Determine vertebral level (approximate based on slice position)
z_fraction = l3_slice / nz
if z_fraction < 0.3:
    vertebral_level = "L4"
elif z_fraction < 0.5:
    vertebral_level = "L3"
elif z_fraction < 0.7:
    vertebral_level = "L2"
else:
    vertebral_level = "L1"

print(f"Ground truth muscle metrics at L3:")
print(f"  Muscle area: {muscle_area_cm2:.1f} cm²")
print(f"  Mean HU: {mean_hu:.1f}")
print(f"  Std HU: {std_hu:.1f}")
print(f"  Patient sex: {patient_sex}")
print(f"  Threshold: {threshold} HU")
print(f"  Myosteatosis: {'Present' if myosteatosis_present else 'Absent'}")

# Save ground truth segmentation
gt_seg_path = os.path.join(gt_dir, f"{case_id}_muscle_gt.nii.gz")
gt_nii = nib.Nifti1Image(muscle_mask_3d, ct_nii.affine, ct_nii.header)
nib.save(gt_nii, gt_seg_path)
print(f"Ground truth segmentation saved: {gt_seg_path}")

# Save ground truth metrics
gt_metrics = {
    "case_id": case_id,
    "patient_sex": patient_sex,
    "l3_slice_index": int(l3_slice),
    "vertebral_level": vertebral_level,
    "muscle_area_cm2": float(round(muscle_area_cm2, 2)),
    "mean_hu": float(round(mean_hu, 2)),
    "std_hu": float(round(std_hu, 2)),
    "median_hu": float(round(median_hu, 2)),
    "myosteatosis_threshold": int(threshold),
    "myosteatosis_present": myosteatosis_present,
    "classification": "Myosteatosis" if myosteatosis_present else "Normal",
    "ct_shape": list(ct_data.shape),
    "voxel_spacing_mm": [float(s) for s in spacing],
    "muscle_voxel_count": int(np.sum(muscle_mask_2d)),
}

gt_json_path = os.path.join(gt_dir, f"{case_id}_muscle_gt.json")
with open(gt_json_path, "w") as f:
    json.dump(gt_metrics, f, indent=2)
print(f"Ground truth metrics saved: {gt_json_path}")
PYEOF

# Record initial state
rm -f /tmp/myosteatosis_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/muscle_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/myosteatosis_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

# Create a Slicer Python script to load the CT
cat > /tmp/load_amos_muscle.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"
patient_sex = "$PATIENT_SEX"

print(f"Loading AMOS CT scan: {case_id}...")
print(f"Patient sex: {patient_sex}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName(f"AbdominalCT_{patient_sex}")

    # Set soft tissue window for muscle visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard soft tissue window
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Navigate to approximate L3 level (middle of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    z_center = (bounds[4] + bounds[5]) / 2
    z_l3 = bounds[4] + 0.45 * (bounds[5] - bounds[4])  # Approximate L3

    # Set axial view to L3 level
    redWidget = slicer.app.layoutManager().sliceWidget("Red")
    redLogic = redWidget.sliceLogic()
    redNode = redLogic.GetSliceNode()
    redNode.SetSliceOffset(z_l3)

    # Set coronal and sagittal to center
    for color, idx in [("Green", 1), ("Yellow", 0)]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = (bounds[idx*2] + bounds[idx*2+1]) / 2
        sliceNode.SetSliceOffset(center)

    print(f"CT loaded with soft tissue window (W=400, L=40)")
    print(f"Navigated to approximate L3 level")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

# Update window title to show patient sex
mainWindow = slicer.util.mainWindow()
mainWindow.setWindowTitle(f"3D Slicer - Myosteatosis Assessment - Patient Sex: {patient_sex}")

print("Setup complete - ready for muscle quality assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_muscle.py > /tmp/slicer_launch.log 2>&1 &

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

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/myosteatosis_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Muscle Quality Assessment (Myosteatosis)"
echo "================================================"
echo ""
echo "PATIENT SEX: $PATIENT_SEX"
echo ""
echo "Your goal:"
echo "  1. Navigate to L3 vertebral level (mid-vertebral body)"
echo "  2. Segment skeletal muscle (psoas + paraspinal muscles)"
echo "  3. Measure mean HU within muscle segmentation"
echo "  4. Classify myosteatosis status"
echo ""
echo "Diagnostic thresholds:"
echo "  - Male: Myosteatosis if mean HU ≤ 41"
echo "  - Female: Myosteatosis if mean HU ≤ 33"
echo ""
echo "Muscle HU range for segmentation: -29 to +150 HU"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/muscle_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/AMOS/myosteatosis_report.json"
echo ""