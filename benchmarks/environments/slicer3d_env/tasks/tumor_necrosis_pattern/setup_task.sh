#!/bin/bash
echo "=== Setting up Tumor Necrosis Pattern Analysis Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

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

# Verify ground truth exists (hidden from agent)
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Pre-compute ground truth statistics for necrosis pattern task
echo "Computing ground truth necrosis statistics..."
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
gt_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
stats_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_necrosis_stats.json"

print(f"Loading ground truth: {gt_path}")
seg = nib.load(gt_path)
data = seg.get_fdata().astype(np.int32)
voxel_vol = float(np.prod(seg.header.get_zooms()[:3]))

# BraTS labels: 1=necrotic, 2=edema, 4=enhancing
enhancing_voxels = int(np.sum(data == 4))
necrotic_voxels = int(np.sum(data == 1))

enhancing_ml = enhancing_voxels * voxel_vol / 1000.0
necrotic_ml = necrotic_voxels * voxel_vol / 1000.0
total_core_ml = enhancing_ml + necrotic_ml

necrosis_ratio = necrotic_ml / total_core_ml if total_core_ml > 0 else 0

# Determine ground truth pattern
if enhancing_ml < 1.0:
    pattern = "Non-enhancing"
elif necrosis_ratio < 0.2:
    pattern = "Solid"
elif necrosis_ratio > 0.3:
    pattern = "Ring-enhancing"
else:
    pattern = "Heterogeneous"

stats = {
    "sample_id": sample_id,
    "enhancing_volume_ml": round(enhancing_ml, 2),
    "necrotic_volume_ml": round(necrotic_ml, 2),
    "total_core_volume_ml": round(total_core_ml, 2),
    "necrosis_ratio": round(necrosis_ratio, 3),
    "enhancement_pattern": pattern,
    "enhancing_voxels": enhancing_voxels,
    "necrotic_voxels": necrotic_voxels,
    "voxel_volume_mm3": round(voxel_vol, 4)
}

with open(stats_path, 'w') as f:
    json.dump(stats, f, indent=2)

print(f"Ground truth necrosis stats computed:")
print(f"  Enhancing: {enhancing_ml:.2f} mL ({enhancing_voxels} voxels)")
print(f"  Necrotic: {necrotic_ml:.2f} mL ({necrotic_voxels} voxels)")
print(f"  Ratio: {necrosis_ratio:.3f}")
print(f"  Pattern: {pattern}")
print(f"  Saved to: {stats_path}")
PYEOF

# Ensure output directory exists and is clean
mkdir -p "$BRATS_DIR"
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true

# Clear any previous agent outputs
rm -f "$BRATS_DIR/enhancement_segmentation.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/enhancement_segmentation.nii" 2>/dev/null || true
rm -f "$BRATS_DIR/necrosis_report.json" 2>/dev/null || true
rm -f /tmp/necrosis_task_result.json 2>/dev/null || true

# Record that outputs don't exist at start
echo "false" > /tmp/seg_existed_at_start.txt
echo "false" > /tmp/report_existed_at_start.txt

# Create a Slicer Python script to load all volumes
cat > /tmp/load_necrosis_volumes.py << 'PYEOF'
import slicer
import os

sample_dir = os.environ.get("SAMPLE_DIR", "/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000")
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")

# Define volumes to load - T1ce is primary for this task
volumes = [
    (f"{sample_id}_t1ce.nii.gz", "T1ce_Contrast"),
    (f"{sample_id}_t1.nii.gz", "T1_PreContrast"),
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("=" * 60)
print("Loading BraTS MRI volumes for Necrosis Pattern Analysis...")
print("=" * 60)
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"  -> Loaded: {node.GetName()}")
        else:
            print(f"  -> ERROR loading {filepath}")
    else:
        print(f"  -> WARNING: File not found: {filepath}")

print(f"\nLoaded {len(loaded_nodes)} volumes")

# Set up the views with T1ce as primary (for enhancement analysis)
if loaded_nodes:
    t1ce_node = None
    for node in loaded_nodes:
        if "T1ce" in node.GetName() or "Contrast" in node.GetName():
            t1ce_node = node
            break
    
    if not t1ce_node:
        t1ce_node = loaded_nodes[0]
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(t1ce_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
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

print("\n" + "=" * 60)
print("Setup complete - ready for necrosis pattern analysis task")
print("=" * 60)
print("\nTIP: Compare T1ce_Contrast with T1_PreContrast to identify")
print("     enhancing regions (bright on T1ce but not on T1)")
PYEOF

# Set environment variables for the Python script
export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" \
    /opt/Slicer/Slicer --python-script /tmp/load_necrosis_volumes.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volumes to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/necrosis_initial.png ga

echo ""
echo "=========================================================="
echo "TASK: Tumor Necrosis and Enhancement Pattern Analysis"
echo "=========================================================="
echo ""
echo "You are given a brain MRI with a glioma. Analyze the tumor's"
echo "internal characteristics by identifying enhancing and necrotic"
echo "components."
echo ""
echo "Loaded volumes:"
echo "  - T1ce_Contrast: Post-contrast (shows enhancement)"
echo "  - T1_PreContrast: Pre-contrast (for comparison)"
echo "  - FLAIR, T2: Additional sequences"
echo ""
echo "Your tasks:"
echo "  1. Compare T1ce vs T1 to identify enhancing regions"
echo "  2. Create TWO segments in Segment Editor:"
echo "     - 'Enhancing_Tumor': Bright on T1ce (enhancing rim)"
echo "     - 'Necrotic_Core': Dark center on T1ce (non-enhancing)"
echo "  3. Use Segment Statistics for volumes (mL)"
echo "  4. Calculate necrosis ratio and classify pattern"
echo ""
echo "Enhancement patterns:"
echo "  - Ring-enhancing: Rim + central necrosis (ratio > 0.3)"
echo "  - Solid: Homogeneous enhancement (ratio < 0.2)"
echo "  - Heterogeneous: Patchy enhancement"
echo "  - Non-enhancing: Minimal enhancement (<1 mL)"
echo ""
echo "Save outputs:"
echo "  - ~/Documents/SlicerData/BraTS/enhancement_segmentation.nii.gz"
echo "  - ~/Documents/SlicerData/BraTS/necrosis_report.json"
echo ""
echo "=========================================================="