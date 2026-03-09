#!/bin/bash
echo "=== Setting up Correct AI Segmentation Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using BraTS sample: $SAMPLE_ID"
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

# Verify BraTS data exists
SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
if [ ! -d "$SAMPLE_DIR" ]; then
    echo "ERROR: BraTS sample directory not found at $SAMPLE_DIR"
    exit 1
fi

FLAIR_FILE="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    exit 1
fi

echo "BraTS data verified at: $SAMPLE_DIR"

# Create broken segmentation (AI segmentation with deliberate errors)
echo "Creating AI segmentation with deliberate errors..."
export SAMPLE_ID BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/create_broken_segmentation.sh

AI_SEG="$BRATS_DIR/ai_segmentation.nii.gz"
if [ ! -f "$AI_SEG" ]; then
    echo "ERROR: AI segmentation not created at $AI_SEG"
    exit 1
fi

echo "AI segmentation created at: $AI_SEG"

# Record initial state - check if corrected file already exists
CORRECTED_PATH="$BRATS_DIR/corrected_segmentation.nii.gz"
if [ -f "$CORRECTED_PATH" ]; then
    rm -f "$CORRECTED_PATH"
    echo "Removed pre-existing corrected segmentation"
fi

# Record initial Dice score (AI seg vs ground truth)
echo "Computing initial Dice score..."
python3 << PYEOF
import json
import sys
import os

try:
    import numpy as np
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy", "nibabel"])
    import numpy as np
    import nibabel as nib

sample_id = "$SAMPLE_ID"
brats_dir = "$BRATS_DIR"
gt_dir = "$GROUND_TRUTH_DIR"

# Load AI segmentation
ai_path = os.path.join(brats_dir, "ai_segmentation.nii.gz")
gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

ai_nii = nib.load(ai_path)
gt_nii = nib.load(gt_path)

ai_data = ai_nii.get_fdata().astype(np.int32)
gt_data = gt_nii.get_fdata().astype(np.int32)

# Calculate initial Dice
ai_binary = (ai_data > 0)
gt_binary = (gt_data > 0)

intersection = np.sum(ai_binary & gt_binary)
dice = 2 * intersection / (np.sum(ai_binary) + np.sum(gt_binary)) if (np.sum(ai_binary) + np.sum(gt_binary)) > 0 else 0

# Calculate error metrics
false_positives = np.sum(ai_binary & ~gt_binary)
false_negatives = np.sum(gt_binary & ~ai_binary)

initial_state = {
    "sample_id": sample_id,
    "initial_dice": float(dice),
    "ai_tumor_voxels": int(np.sum(ai_binary)),
    "gt_tumor_voxels": int(np.sum(gt_binary)),
    "initial_false_positives": int(false_positives),
    "initial_false_negatives": int(false_negatives),
    "task_start_time": int(open("/tmp/task_start_time.txt").read().strip())
}

with open("/tmp/initial_state.json", "w") as f:
    json.dump(initial_state, f, indent=2)

print(f"Initial Dice (AI vs GT): {dice:.4f}")
print(f"False positives: {false_positives} voxels")
print(f"False negatives: {false_negatives} voxels")
PYEOF

# Kill any existing Slicer
echo "Preparing 3D Slicer..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load data and AI segmentation
cat > /tmp/load_brats_task.py << 'PYEOF'
import slicer
import os

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")

sample_dir = os.path.join(brats_dir, sample_id)

# Load FLAIR as main background (best for tumor visualization)
flair_path = os.path.join(sample_dir, f"{sample_id}_flair.nii.gz")
if os.path.exists(flair_path):
    slicer.util.loadVolume(flair_path, {"name": "FLAIR"})
    print(f"Loaded FLAIR: {flair_path}")

# Load T1ce for reference
t1ce_path = os.path.join(sample_dir, f"{sample_id}_t1ce.nii.gz")
if os.path.exists(t1ce_path):
    slicer.util.loadVolume(t1ce_path, {"name": "T1ce"})
    print(f"Loaded T1ce: {t1ce_path}")

# Load AI segmentation as labelmap/segmentation
ai_seg_path = os.path.join(brats_dir, "ai_segmentation.nii.gz")
if os.path.exists(ai_seg_path):
    seg_node = slicer.util.loadSegmentation(ai_seg_path, {"name": "AI_Segmentation"})
    if seg_node:
        print(f"Loaded AI segmentation: {ai_seg_path}")
        # Make it visible
        seg_node.CreateDefaultDisplayNodes()
        display_node = seg_node.GetDisplayNode()
        if display_node:
            display_node.SetVisibility(True)
            display_node.SetOpacity2DFill(0.5)
            display_node.SetOpacity2DOutline(1.0)
    else:
        # Try loading as labelmap and converting
        labelmap_node = slicer.util.loadLabelVolume(ai_seg_path, {"name": "AI_Segmentation_Labelmap"})
        if labelmap_node:
            print("Loaded as labelmap, converting to segmentation...")
            seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode", "AI_Segmentation")
            slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmap_node, seg_node)
            slicer.mrmlScene.RemoveNode(labelmap_node)
            seg_node.CreateDefaultDisplayNodes()

# Set FLAIR as background in all views
layout_manager = slicer.app.layoutManager()
for view_name in ["Red", "Green", "Yellow"]:
    slice_widget = layout_manager.sliceWidget(view_name)
    if slice_widget:
        slice_logic = slice_widget.sliceLogic()
        composite_node = slice_logic.GetSliceCompositeNode()
        
        # Find FLAIR volume
        flair_node = slicer.util.getNode("FLAIR")
        if flair_node:
            composite_node.SetBackgroundVolumeID(flair_node.GetID())

# Center the views on the data
slicer.util.resetSliceViews()

print("Data loading complete. Ready for segmentation editing.")
PYEOF

# Launch Slicer with the loading script
echo "Launching 3D Slicer with BraTS data and AI segmentation..."
export SAMPLE_ID BRATS_DIR
su - ga -c "DISPLAY=:1 SAMPLE_ID='$SAMPLE_ID' BRATS_DIR='$BRATS_DIR' /opt/Slicer/Slicer --python-script /tmp/load_brats_task.py > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 15

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus the window
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Correct AI Segmentation Errors"
echo ""
echo "The AI segmentation has TWO errors to fix:"
echo "  1. OVER-SEGMENTATION: A false positive blob (disconnected from main tumor)"
echo "  2. UNDER-SEGMENTATION: A missing region at the tumor edge"
echo ""
echo "Use Segment Editor tools to:"
echo "  - Remove the false positive (use Erase, Scissors, or Islands effect)"
echo "  - Fill in the missing tumor region (use Paint or Level tracing)"
echo ""
echo "Save corrected segmentation to:"
echo "  $BRATS_DIR/corrected_segmentation.nii.gz"
echo ""