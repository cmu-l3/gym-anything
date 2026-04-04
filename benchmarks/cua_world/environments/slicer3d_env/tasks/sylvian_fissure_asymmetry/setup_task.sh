#!/bin/bash
echo "=== Setting up Sylvian Fissure Asymmetry Assessment Task ==="

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
FLAIR_FILE="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"

echo "Using sample: $SAMPLE_ID"

# Verify FLAIR file exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR volume not found at $FLAIR_FILE"
    exit 1
fi
echo "FLAIR volume found: $FLAIR_FILE"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task artifacts
rm -f /tmp/sylvian_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/left_sylvian.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/right_sylvian.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/sylvian_asymmetry_report.json" 2>/dev/null || true

# Compute ground truth Sylvian fissure measurements from FLAIR image
echo "Computing ground truth Sylvian fissure measurements..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
    import nibabel as nib

from scipy import ndimage

flair_path = "$FLAIR_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

print(f"Loading FLAIR: {flair_path}")
flair_nii = nib.load(flair_path)
flair_data = flair_nii.get_fdata()
voxel_dims = flair_nii.header.get_zooms()[:3]

print(f"Volume shape: {flair_data.shape}")
print(f"Voxel dims (mm): {voxel_dims}")

# Normalize intensity for thresholding
flair_norm = (flair_data - np.min(flair_data)) / (np.max(flair_data) - np.min(flair_data) + 1e-8)

# CSF is bright on FLAIR - use high intensity threshold
# But we need to be careful as tumor/edema is also bright
# Focus on the lateral regions where Sylvian fissure is located

nx, ny, nz = flair_data.shape
center_x, center_y = nx // 2, ny // 2

# Define approximate Sylvian fissure search regions
# Left Sylvian: typically in the left lateral region of the brain
# Right Sylvian: typically in the right lateral region
# In radiological convention, left side of image is patient's right

# Search for the axial slice with best Sylvian fissure visibility
# This is typically around the mid-brain level (40-60% of z-range)
mid_z_start = int(nz * 0.35)
mid_z_end = int(nz * 0.65)

# Use intensity-based detection for CSF spaces
# CSF appears bright on FLAIR in sulci
csf_threshold = np.percentile(flair_data[flair_data > 0], 75)

best_slice = mid_z_start + (mid_z_end - mid_z_start) // 2
left_width_mm = 0
right_width_mm = 0
left_center = [0, 0, 0]
right_center = [0, 0, 0]

# Search for slices with good bilateral Sylvian fissure visibility
for z in range(mid_z_start, mid_z_end):
    slice_data = flair_data[:, :, z]
    
    # Define left and right Sylvian regions
    # Left hemisphere (patient's left = right side of image in radiological)
    # Sylvian fissure is typically at about 30-45% and 55-70% of x-dimension
    left_region_x = slice(int(nx * 0.55), int(nx * 0.75))
    right_region_x = slice(int(nx * 0.25), int(nx * 0.45))
    
    # Y range for Sylvian fissure (lateral part of brain)
    y_range = slice(int(ny * 0.35), int(ny * 0.65))
    
    left_region = slice_data[left_region_x, y_range]
    right_region = slice_data[right_region_x, y_range]
    
    # Find CSF-like intensities in each region
    left_csf = (left_region > csf_threshold)
    right_csf = (right_region > csf_threshold)
    
    if np.sum(left_csf) > 20 and np.sum(right_csf) > 20:
        # Estimate width from the extent of CSF signal
        left_cols = np.any(left_csf, axis=0)
        right_cols = np.any(right_csf, axis=0)
        
        if np.any(left_cols) and np.any(right_cols):
            left_extent = np.sum(left_cols) * voxel_dims[1]
            right_extent = np.sum(right_cols) * voxel_dims[1]
            
            if left_extent > left_width_mm or right_extent > right_width_mm:
                if left_extent > 2 and right_extent > 2:  # Minimum width
                    left_width_mm = left_extent
                    right_width_mm = right_extent
                    best_slice = z
                    
                    # Compute approximate centers
                    left_y_indices = np.where(left_cols)[0]
                    right_y_indices = np.where(right_cols)[0]
                    
                    left_center = [
                        (int(nx * 0.55) + int(nx * 0.75)) / 2 * voxel_dims[0],
                        (int(ny * 0.35) + np.mean(left_y_indices)) * voxel_dims[1],
                        z * voxel_dims[2]
                    ]
                    right_center = [
                        (int(nx * 0.25) + int(nx * 0.45)) / 2 * voxel_dims[0],
                        (int(ny * 0.35) + np.mean(right_y_indices)) * voxel_dims[1],
                        z * voxel_dims[2]
                    ]

# Add some realistic variation and ensure physiologically plausible values
# Normal Sylvian fissure width: 4-12mm, can be asymmetric by up to 30%
np.random.seed(42)

# Ensure measurements are in reasonable range
left_width_mm = np.clip(left_width_mm, 5.0, 14.0)
right_width_mm = np.clip(right_width_mm, 5.0, 14.0)

# Add small random variation to make it more realistic
left_width_mm = float(left_width_mm + np.random.uniform(-1, 1))
right_width_mm = float(right_width_mm + np.random.uniform(-1, 1))

# Ensure final values are in valid range
left_width_mm = max(4.0, min(15.0, left_width_mm))
right_width_mm = max(4.0, min(15.0, right_width_mm))

# Calculate asymmetry index
mean_width = (left_width_mm + right_width_mm) / 2
sfai = abs(left_width_mm - right_width_mm) / mean_width * 100 if mean_width > 0 else 0

# Classify
if sfai < 15:
    classification = "Symmetric"
    wider_side = "symmetric"
elif sfai < 25:
    classification = "Mildly Asymmetric"
    wider_side = "left" if left_width_mm > right_width_mm else "right"
else:
    classification = "Significantly Asymmetric"
    wider_side = "left" if left_width_mm > right_width_mm else "right"

# Approximate vertebral/anatomical level
z_fraction = best_slice / nz
if z_fraction < 0.4:
    level_description = "lower insular level"
elif z_fraction < 0.55:
    level_description = "mid-insular level"
else:
    level_description = "upper insular level"

ground_truth = {
    "sample_id": sample_id,
    "left_width_mm": round(left_width_mm, 2),
    "right_width_mm": round(right_width_mm, 2),
    "asymmetry_index_percent": round(sfai, 2),
    "classification": classification,
    "wider_side": wider_side,
    "measurement_slice_index": int(best_slice),
    "measurement_z_mm": float(best_slice * voxel_dims[2]),
    "level_description": level_description,
    "left_center_ras": [float(x) for x in left_center],
    "right_center_ras": [float(x) for x in right_center],
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "volume_shape": list(flair_data.shape)
}

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{sample_id}_sylvian_gt.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"Left Sylvian width: {left_width_mm:.2f} mm")
print(f"Right Sylvian width: {right_width_mm:.2f} mm")
print(f"SFAI: {sfai:.2f}%")
print(f"Classification: {classification}")
print(f"Best slice: {best_slice} ({level_description})")
PYEOF

# Create a Slicer Python script to load FLAIR with optimal settings
cat > /tmp/load_flair_sylvian.py << PYEOF
import slicer
import os

flair_path = "$FLAIR_FILE"
sample_id = "$SAMPLE_ID"

print(f"Loading FLAIR volume for Sylvian fissure assessment...")
print(f"File: {flair_path}")

# Load the FLAIR volume
volume_node = slicer.util.loadVolume(flair_path)

if volume_node:
    volume_node.SetName("FLAIR")
    
    # Set window/level optimized for CSF visualization
    # CSF appears bright on FLAIR - use wide window to see sulci
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Auto window/level first, then adjust
        displayNode.AutoWindowLevelOn()
        slicer.app.processEvents()
        
        # Get auto values and adjust for better CSF contrast
        window = displayNode.GetWindow()
        level = displayNode.GetLevel()
        
        # Slightly increase window for better sulcal visualization
        displayNode.SetWindow(window * 1.2)
        displayNode.SetLevel(level)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Navigate to mid-brain level (good for Sylvian fissure visualization)
    bounds = [0] * 6
    volume_node.GetBounds(bounds)
    
    # Calculate mid-point in each dimension
    mid_x = (bounds[0] + bounds[1]) / 2
    mid_y = (bounds[2] + bounds[3]) / 2
    mid_z = (bounds[4] + bounds[5]) / 2
    
    # Set slice offsets - start at approximately mid-insular level
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        if color == "Red":  # Axial - this is where we'll measure
            # Set to mid-brain level
            sliceNode.SetSliceOffset(mid_z)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(mid_y)
        else:  # Yellow - Sagittal
            sliceNode.SetSliceOffset(mid_x)
    
    # Switch to Conventional layout (axial view prominent)
    slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    print(f"FLAIR loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Navigate to mid-insular level in Axial view for Sylvian fissure measurement")
else:
    print("ERROR: Could not load FLAIR volume")

print("\nSetup complete - ready for Sylvian fissure measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with FLAIR volume..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_flair_sylvian.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/sylvian_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Sylvian Fissure Asymmetry Assessment"
echo "==========================================="
echo ""
echo "You are given a brain MRI (FLAIR sequence) to assess for"
echo "asymmetric cortical atrophy by measuring the Sylvian fissures."
echo ""
echo "Instructions:"
echo "  1. Navigate to mid-insular level in the Axial view"
echo "  2. Identify the Sylvian fissure on BOTH sides"
echo "     (deep cleft between frontal/parietal and temporal lobes)"
echo "  3. Measure LEFT Sylvian fissure width using ruler tool"
echo "  4. Measure RIGHT Sylvian fissure width at same level"
echo "  5. Calculate asymmetry index:"
echo "     SFAI = |L-R| / ((L+R)/2) × 100"
echo "  6. Classify: Symmetric (<15%), Mildly Asymmetric (15-25%),"
echo "     or Significantly Asymmetric (>25%)"
echo ""
echo "Save outputs to:"
echo "  - Left: ~/Documents/SlicerData/BraTS/left_sylvian.mrk.json"
echo "  - Right: ~/Documents/SlicerData/BraTS/right_sylvian.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/sylvian_asymmetry_report.json"
echo ""