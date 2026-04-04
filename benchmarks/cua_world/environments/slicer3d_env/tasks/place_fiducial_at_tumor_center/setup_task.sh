#!/bin/bash
echo "=== Setting up Place Fiducial at Tumor Center Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"

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

# Record initial state
rm -f /tmp/fiducial_tumor_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_center.mrk.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create Python script to load data, position to tumor, and compute center
cat > /tmp/setup_fiducial_task.py << 'PYEOF'
import slicer
import os
import numpy as np

sample_dir = os.environ.get('SAMPLE_DIR', '/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000')
sample_id = os.environ.get('SAMPLE_ID', 'BraTS2021_00000')

print(f"Loading FLAIR from {sample_dir}...")

# Load FLAIR volume
flair_path = os.path.join(sample_dir, f"{sample_id}_flair.nii.gz")
if os.path.exists(flair_path):
    flair_node = slicer.util.loadVolume(flair_path)
    flair_node.SetName("FLAIR")
else:
    print(f"ERROR: {flair_path} not found")
    exit(1)

# Set FLAIR as background
for color in ["Red", "Green", "Yellow"]:
    sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
    sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

# Find slice with maximum tumor
array = slicer.util.arrayFromVolume(flair_node)
slice_intensities = np.sum(array, axis=(1, 2))
best_slice_idx = np.argmax(slice_intensities)

spacing = flair_node.GetSpacing()
origin = flair_node.GetOrigin()
best_slice_position = origin[2] + best_slice_idx * spacing[2]

# Set axial slice position
red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
red_logic.SetSliceOffset(best_slice_position)

# Find tumor center in this slice
tumor_slice = array[best_slice_idx, :, :]
threshold = np.percentile(tumor_slice, 95)
tumor_mask = tumor_slice > threshold

# Find centroid
rows, cols = np.where(tumor_mask)
if len(rows) > 0 and len(cols) > 0:
    center_row = np.mean(rows)
    center_col = np.mean(cols)

    # Convert to RAS coordinates
    center_i = center_col
    center_j = center_row
    center_k = best_slice_idx

    # Simple conversion (assuming RAS orientation)
    center_r = origin[0] + center_i * spacing[0]
    center_a = origin[1] + center_j * spacing[1]
    center_s = origin[2] + center_k * spacing[2]

    print(f"Tumor center (RAS): [{center_r:.1f}, {center_a:.1f}, {center_s:.1f}]")

    # Save ground truth
    with open('/tmp/tumor_center_gt.txt', 'w') as f:
        f.write(f"{center_r:.2f},{center_a:.2f},{center_s:.2f}")
else:
    print("Warning: Could not find tumor center")
    with open('/tmp/tumor_center_gt.txt', 'w') as f:
        f.write("0,0,0")

slicer.util.resetSliceViews()

# Navigate to Markups module
slicer.util.selectModule("Markups")

print("Setup complete - tumor visible, ready for fiducial placement")
PYEOF

# Kill existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"

# Launch Slicer
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/setup_fiducial_task.py > /tmp/slicer_launch.log 2>&1 &

wait_for_slicer 120
sleep 10

# Configure window
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    focus_window "$WID"
fi

sleep 3
take_screenshot /tmp/fiducial_initial.png ga

echo "=== Setup Complete ==="
