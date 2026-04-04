#!/bin/bash
echo "=== Setting up Bicaudate Index Measurement Task ==="

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

# Verify T1 file exists (we use T1 for this measurement)
T1_FILE="$SAMPLE_DIR/${SAMPLE_ID}_t1.nii.gz"
if [ ! -f "$T1_FILE" ]; then
    echo "ERROR: T1 volume not found at $T1_FILE"
    exit 1
fi
echo "T1 volume found: $T1_FILE"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time

# Clean up any previous task artifacts
rm -f /tmp/bicaudate_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/intercaudate_measurement.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/brain_width_measurement.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/bicaudate_report.json" 2>/dev/null || true

# Generate ground truth measurements
echo "Computing ground truth bicaudate measurements..."
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
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy import ndimage

t1_path = "$T1_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

os.makedirs(gt_dir, exist_ok=True)

print(f"Loading T1 volume: {t1_path}")
t1_nii = nib.load(t1_path)
t1_data = t1_nii.get_fdata()
voxel_dims = t1_nii.header.get_zooms()[:3]

print(f"Volume shape: {t1_data.shape}")
print(f"Voxel dimensions: {voxel_dims}")

# Normalize data for processing
t1_norm = (t1_data - t1_data.min()) / (t1_data.max() - t1_data.min() + 1e-8)

# Find brain mask (simple thresholding)
brain_threshold = 0.1
brain_mask = t1_norm > brain_threshold

# Find ventricles (CSF appears dark on T1)
# CSF is typically in lower intensity range within brain
brain_intensities = t1_norm[brain_mask]
csf_threshold = np.percentile(brain_intensities, 15)  # Lower 15% of brain intensities

# Create CSF/ventricle mask
csf_mask = brain_mask & (t1_norm < csf_threshold)

# Find the best axial slice showing frontal horns with caudate
# We look for slices in the middle-upper brain region
nz = t1_data.shape[2]
mid_slice = nz // 2
search_range = range(int(mid_slice - nz * 0.2), int(mid_slice + nz * 0.15))

best_slice = mid_slice
best_score = 0
ic_distances = []

for z in search_range:
    slice_mask = csf_mask[:, :, z]
    if np.sum(slice_mask) < 50:
        continue
    
    # Label connected components
    labeled, num_features = ndimage.label(slice_mask)
    if num_features < 2:
        continue
    
    # Find left and right ventricle candidates (separated by midline)
    center_x = t1_data.shape[0] // 2
    left_mask = (labeled > 0) & (np.arange(t1_data.shape[0])[:, None] < center_x)
    right_mask = (labeled > 0) & (np.arange(t1_data.shape[0])[:, None] >= center_x)
    
    if np.sum(left_mask) < 20 or np.sum(right_mask) < 20:
        continue
    
    # Find the medial edges of each ventricle (closest to midline)
    left_coords = np.argwhere(left_mask)
    right_coords = np.argwhere(right_mask)
    
    if len(left_coords) == 0 or len(right_coords) == 0:
        continue
    
    # Medial edge of left ventricle (maximum x)
    left_medial_x = np.max(left_coords[:, 0])
    # Medial edge of right ventricle (minimum x)
    right_medial_x = np.min(right_coords[:, 0])
    
    # Intercaudate distance in voxels
    ic_voxels = right_medial_x - left_medial_x
    if ic_voxels <= 0:
        continue
    
    # Convert to mm
    ic_mm = ic_voxels * voxel_dims[0]
    
    # Score based on typical frontal horn appearance
    # Good slice has moderate ventricle size and reasonable IC
    ventricle_area = np.sum(slice_mask)
    if 100 < ventricle_area < 2000 and 5 < ic_mm < 25:
        score = ventricle_area * (1 - abs(ic_mm - 12) / 15)
        if score > best_score:
            best_score = score
            best_slice = z
            
print(f"Selected axial slice: {best_slice}")

# Compute final measurements on best slice
slice_mask = csf_mask[:, :, best_slice]
brain_slice = brain_mask[:, :, best_slice]

# Intercaudate distance
labeled, num_features = ndimage.label(slice_mask)
center_x = t1_data.shape[0] // 2

left_mask = (labeled > 0) & (np.arange(t1_data.shape[0])[:, None] < center_x)
right_mask = (labeled > 0) & (np.arange(t1_data.shape[0])[:, None] >= center_x)

left_coords = np.argwhere(left_mask)
right_coords = np.argwhere(right_mask)

if len(left_coords) > 0 and len(right_coords) > 0:
    left_medial_x = np.max(left_coords[:, 0])
    right_medial_x = np.min(right_coords[:, 0])
    ic_voxels = right_medial_x - left_medial_x
    intercaudate_mm = float(ic_voxels * voxel_dims[0])
else:
    # Fallback to center estimation
    intercaudate_mm = 12.0
    
print(f"Intercaudate distance: {intercaudate_mm:.2f} mm")

# Brain width at same slice
brain_row_sums = np.sum(brain_slice, axis=1)
brain_rows = np.where(brain_row_sums > 0)[0]
if len(brain_rows) > 0:
    brain_width_voxels = brain_rows[-1] - brain_rows[0]
    brain_width_mm = float(brain_width_voxels * voxel_dims[0])
else:
    brain_width_mm = 140.0

print(f"Brain width: {brain_width_mm:.2f} mm")

# Calculate bicaudate index
bicaudate_index = intercaudate_mm / brain_width_mm if brain_width_mm > 0 else 0.0
print(f"Bicaudate index: {bicaudate_index:.4f}")

# Clinical classification
if bicaudate_index < 0.15:
    classification = "Normal"
elif bicaudate_index <= 0.18:
    classification = "Borderline"
else:
    classification = "Atrophic"

print(f"Classification: {classification}")

# Save ground truth
gt_data = {
    "sample_id": sample_id,
    "intercaudate_distance_mm": round(intercaudate_mm, 2),
    "brain_width_mm": round(brain_width_mm, 2),
    "bicaudate_index": round(bicaudate_index, 4),
    "classification": classification,
    "optimal_slice": int(best_slice),
    "volume_shape": list(t1_data.shape),
    "voxel_dims_mm": [float(v) for v in voxel_dims]
}

gt_path = os.path.join(gt_dir, f"{sample_id}_bicaudate_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(json.dumps(gt_data, indent=2))
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_bicaudate_gt.json" ]; then
    echo "ERROR: Failed to generate ground truth measurements"
    exit 1
fi
echo "Ground truth measurements generated successfully"

# Create a Slicer Python script to load the T1 volume
cat > /tmp/load_t1_for_bicaudate.py << PYEOF
import slicer
import os

t1_path = "$T1_FILE"
sample_id = "$SAMPLE_ID"

print(f"Loading T1 volume for bicaudate measurement: {sample_id}...")

volume_node = slicer.util.loadVolume(t1_path)

if volume_node:
    volume_node.SetName("T1_Brain")
    
    # Set appropriate window/level for brain MRI
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Auto window/level usually works well for brain MRI
        displayNode.SetAutoWindowLevel(True)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Set layout to conventional (axial main view)
    layoutManager = slicer.app.layoutManager()
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Center approximately on the ventricle region
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2
    
    # Set Red (axial) slice to approximate ventricle level (slightly above center)
    redSliceNode = slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode()
    redSliceNode.SetSliceOffset(center_z + 10)  # Slightly superior
    
    print(f"T1 volume loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load T1 volume")

print("Setup complete - ready for bicaudate index measurement")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script to load T1
echo "Launching 3D Slicer with T1 volume..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_t1_for_bicaudate.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/bicaudate_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Bicaudate Index Measurement"
echo "=================================="
echo ""
echo "You are given a T1-weighted brain MRI. Measure the bicaudate index (BCI)"
echo "to assess for caudate atrophy."
echo ""
echo "Steps:"
echo "  1. Navigate to axial view, find the frontal horns of lateral ventricles"
echo "  2. Identify the caudate nuclei (bulge into ventricle walls)"
echo "  3. Use Markups ruler to measure INTERCAUDATE DISTANCE (IC):"
echo "     - Minimum distance between medial borders of caudate heads"
echo "  4. At SAME slice, measure BRAIN WIDTH (BW):"
echo "     - Inner table to inner table of skull"
echo "  5. Calculate: BCI = IC / BW"
echo "  6. Classify: Normal (<0.15), Borderline (0.15-0.18), Atrophic (>0.18)"
echo ""
echo "Save outputs to ~/Documents/SlicerData/BraTS/:"
echo "  - intercaudate_measurement.mrk.json"
echo "  - brain_width_measurement.mrk.json"
echo "  - bicaudate_report.json"
echo ""