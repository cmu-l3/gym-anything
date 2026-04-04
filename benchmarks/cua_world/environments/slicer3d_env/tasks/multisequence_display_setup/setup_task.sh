#!/bin/bash
echo "=== Setting up Multi-Sequence MRI Display Configuration Task ==="

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

# Verify ground truth exists for fiducial verification
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "WARNING: Ground truth segmentation not found!"
fi

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task outputs
rm -f "$BRATS_DIR/multisequence_comparison.png" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_center.fcsv" 2>/dev/null || true
rm -f "$BRATS_DIR/sequence_comparison_report.json" 2>/dev/null || true
rm -f /tmp/multisequence_task_result.json 2>/dev/null || true

# Calculate tumor centroid from ground truth for verification
echo "Computing tumor centroid for verification..."
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

gt_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
output_path = "/tmp/tumor_centroid_gt.json"

if os.path.exists(gt_path):
    seg = nib.load(gt_path)
    data = seg.get_fdata()
    affine = seg.affine
    
    # Find all tumor voxels (labels 1, 2, 4 in BraTS)
    tumor_mask = (data == 1) | (data == 2) | (data == 4)
    
    if np.any(tumor_mask):
        # Get voxel coordinates of tumor
        coords = np.array(np.where(tumor_mask)).T
        centroid_voxel = coords.mean(axis=0)
        
        # Convert to RAS coordinates using affine
        centroid_homogeneous = np.append(centroid_voxel, 1)
        centroid_ras = affine.dot(centroid_homogeneous)[:3]
        
        # Get bounding box for size estimation
        min_coords = coords.min(axis=0)
        max_coords = coords.max(axis=0)
        voxel_dims = seg.header.get_zooms()[:3]
        tumor_size_mm = (max_coords - min_coords) * np.array(voxel_dims)
        
        result = {
            "centroid_voxel": centroid_voxel.tolist(),
            "centroid_ras": centroid_ras.tolist(),
            "tumor_size_mm": tumor_size_mm.tolist(),
            "total_tumor_voxels": int(np.sum(tumor_mask)),
            "sample_id": "$SAMPLE_ID"
        }
        
        with open(output_path, "w") as f:
            json.dump(result, f, indent=2)
        print(f"Tumor centroid (RAS): {centroid_ras}")
        print(f"Tumor size (mm): {tumor_size_mm}")
    else:
        print("WARNING: No tumor found in ground truth")
else:
    print(f"WARNING: Ground truth not found at {gt_path}")
PYEOF

# Create a Slicer Python script to load all volumes with specific layout
cat > /tmp/load_brats_for_multiview.py << PYEOF
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

print("Loading BraTS MRI volumes...")
loaded_nodes = {}

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name} from {filepath}")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes[display_name] = node
            print(f"    Loaded: {node.GetName()}")
        else:
            print(f"    ERROR loading {filepath}")
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set initial layout to conventional (not Four-Up, agent must change it)
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)

# Set FLAIR as background initially (agent will need to configure others)
if "FLAIR" in loaded_nodes:
    flair_node = loaded_nodes["FLAIR"]
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = layoutManager.sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Navigate to middle of volume
    bounds = [0]*6
    flair_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = layoutManager.sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

print("")
print("Setup complete!")
print("Task: Configure a Four-Up layout with each MRI sequence in a different panel")
print("Available sequences: FLAIR, T1, T1_Contrast, T2")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_for_multiview.py > /tmp/slicer_launch.log 2>&1 &

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

# Take initial screenshot (shows conventional layout, not Four-Up)
take_screenshot /tmp/multisequence_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Multi-Sequence MRI Display Configuration"
echo "================================================"
echo ""
echo "You have a brain tumor case with 4 MRI sequences loaded."
echo "Current layout: Conventional view (single main panel)"
echo ""
echo "Your goal:"
echo "  1. Change to Four-Up (2x2) layout: View > Layout > Four-Up"
echo "  2. Assign each sequence to a panel:"
echo "     - Top-left: FLAIR"
echo "     - Top-right: T1"
echo "     - Bottom-left: T1_Contrast"
echo "     - Bottom-right: T2"
echo "  3. Link views (click chain icon) so they're synchronized"
echo "  4. Navigate to the tumor"
echo "  5. Place a fiducial at tumor center"
echo "  6. Capture screenshot and save report"
echo ""
echo "Output files to create:"
echo "  - Screenshot: ~/Documents/SlicerData/BraTS/multisequence_comparison.png"
echo "  - Fiducial: ~/Documents/SlicerData/BraTS/tumor_center.fcsv"
echo "  - Report: ~/Documents/SlicerData/BraTS/sequence_comparison_report.json"
echo ""