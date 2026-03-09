#!/bin/bash
echo "=== Setting up Measure Visible Tumor Diameter Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"

# Verify FLAIR volume exists
if [ ! -f "$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz" ]; then
    echo "ERROR: FLAIR volume not found!"
    exit 1
fi
echo "FLAIR volume found"

# Record initial state
rm -f /tmp/measure_tumor_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_diameter.mrk.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create Python script to load data and pre-position to tumor slice
cat > /tmp/setup_tumor_measurement.py << 'PYEOF'
import slicer
import os
import numpy as np

sample_dir = os.environ.get('SAMPLE_DIR', '/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000')
sample_id = os.environ.get('SAMPLE_ID', 'BraTS2021_00000')

print(f"Loading FLAIR from {sample_dir}...")

# Load FLAIR volume (best for tumor visualization)
flair_path = os.path.join(sample_dir, f"{sample_id}_flair.nii.gz")
if os.path.exists(flair_path):
    flair_node = slicer.util.loadVolume(flair_path)
    flair_node.SetName("FLAIR")
    print("FLAIR loaded successfully")
else:
    print(f"ERROR: {flair_path} not found")
    exit(1)

# Set FLAIR as background in all slice views
for color in ["Red", "Green", "Yellow"]:
    sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
    sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

# Find the slice with maximum tumor intensity (brightest slice)
# This is where the tumor is most visible
array = slicer.util.arrayFromVolume(flair_node)
# Sum intensity along each axial slice
slice_intensities = np.sum(array, axis=(1, 2))
# Find slice with highest intensity (likely has largest tumor cross-section)
best_slice_idx = np.argmax(slice_intensities)

# Get volume spacing and origin to compute the slice offset
imageData = flair_node.GetImageData()
spacing = flair_node.GetSpacing()
origin = flair_node.GetOrigin()

# Compute the actual position for the best slice
# Array is in IJK order, so best_slice_idx is the K index
best_slice_position = origin[2] + best_slice_idx * spacing[2]

print(f"Best tumor slice: index {best_slice_idx}, position {best_slice_position:.1f}mm")

# Set the red (axial) slice to this position
red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
red_logic.SetSliceOffset(best_slice_position)

# Reset and fit the views
slicer.util.resetSliceViews()

# Record the ground truth for verification
# Measure tumor extent in this slice
tumor_slice = array[best_slice_idx, :, :]
# Simple threshold to find tumor region (high intensity)
threshold = np.percentile(tumor_slice, 95)  # Top 5% brightest
tumor_mask = tumor_slice > threshold

# Find bounding box of tumor
rows = np.any(tumor_mask, axis=1)
cols = np.any(tumor_mask, axis=0)
if np.any(rows) and np.any(cols):
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    # Estimate diameter in mm
    diameter_pixels = max(rmax - rmin, cmax - cmin)
    diameter_mm = diameter_pixels * spacing[0]  # Assuming isotropic in-plane
    print(f"Estimated tumor diameter: {diameter_mm:.1f}mm")

    # Save ground truth
    with open('/tmp/tumor_ground_truth.txt', 'w') as f:
        f.write(f"{diameter_mm:.2f}")
else:
    print("Warning: Could not estimate tumor diameter")
    with open('/tmp/tumor_ground_truth.txt', 'w') as f:
        f.write("45.0")

# Navigate to Markups module
slicer.util.selectModule("Markups")

print("Setup complete - tumor is visible in the axial (red) view")
print("Ready for measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Export variables for the Python script
export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"

# Launch Slicer with the setup script
echo "Launching 3D Slicer with pre-positioned tumor view..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/setup_tumor_measurement.py > /tmp/slicer_launch.log 2>&1 &

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

    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1

    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 3

# Take initial screenshot
take_screenshot /tmp/tumor_initial.png ga

echo "=== Setup Complete ==="
