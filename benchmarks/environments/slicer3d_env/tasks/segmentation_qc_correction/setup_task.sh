#!/bin/bash
echo "=== Setting up Segmentation QC Task ==="

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

# Create broken segmentation for QC task
echo "Creating broken segmentation for QC..."
export BRATS_DIR GROUND_TRUTH_DIR SAMPLE_ID
export GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
export OUTPUT_BROKEN="$BRATS_DIR/ai_segmentation.nii.gz"

/workspace/scripts/create_broken_segmentation.sh

# Verify broken segmentation was created
if [ ! -f "$OUTPUT_BROKEN" ]; then
    echo "ERROR: Failed to create broken segmentation"
    exit 1
fi
echo "Broken segmentation created: $OUTPUT_BROKEN"

# Clean up any previous agent outputs
rm -f "$BRATS_DIR/corrected_segmentation.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/qc_report.json" 2>/dev/null || true

# Calculate and save initial metrics for verification
echo "Calculating initial metrics..."
python3 << 'PYEOF'
import os
import sys
import json

try:
    import numpy as np
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy", "nibabel"])
    import numpy as np
    import nibabel as nib

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")

gt_path = f"{gt_dir}/{sample_id}_seg.nii.gz"
broken_path = f"{brats_dir}/ai_segmentation.nii.gz"

metrics = {"sample_id": sample_id}

if os.path.exists(gt_path) and os.path.exists(broken_path):
    gt_nii = nib.load(gt_path)
    gt = gt_nii.get_fdata() > 0
    broken = nib.load(broken_path).get_fdata() > 0
    
    # Calculate initial Dice
    intersection = np.sum(gt & broken)
    dice = 2 * intersection / (np.sum(gt) + np.sum(broken)) if (np.sum(gt) + np.sum(broken)) > 0 else 0
    
    metrics["initial_dice"] = float(dice)
    metrics["gt_tumor_voxels"] = int(np.sum(gt))
    metrics["broken_tumor_voxels"] = int(np.sum(broken))
    metrics["initial_false_positives"] = int(np.sum(broken & ~gt))
    metrics["initial_false_negatives"] = int(np.sum(gt & ~broken))
    
    # Get voxel spacing for volume calculations
    voxel_dims = gt_nii.header.get_zooms()[:3]
    metrics["voxel_volume_mm3"] = float(np.prod(voxel_dims))
    
    print(f"Initial Dice: {dice:.4f}")
    print(f"False Positives: {metrics['initial_false_positives']}")
    print(f"False Negatives: {metrics['initial_false_negatives']}")
else:
    print(f"ERROR: Could not find GT ({gt_path}) or broken seg ({broken_path})")
    metrics["error"] = "Files not found"

# Save metrics
with open(f"{gt_dir}/initial_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

print(f"Initial metrics saved to {gt_dir}/initial_metrics.json")
PYEOF

# Create Slicer Python script to load data for QC
cat > /tmp/load_qc_data.py << 'PYEOF'
import slicer
import os

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = "/home/ga/Documents/SlicerData/BraTS"
sample_dir = f"{brats_dir}/{sample_id}"
seg_path = f"{brats_dir}/ai_segmentation.nii.gz"

print(f"Loading BraTS data for QC task: {sample_id}")

# Load MRI sequences
volumes_loaded = []
for seq, display_name in [("flair", "FLAIR"), ("t1", "T1"), ("t1ce", "T1_Contrast"), ("t2", "T2")]:
    path = f"{sample_dir}/{sample_id}_{seq}.nii.gz"
    if os.path.exists(path):
        node = slicer.util.loadVolume(path)
        if node:
            node.SetName(display_name)
            volumes_loaded.append(node)
            print(f"  Loaded: {display_name}")

print(f"Loaded {len(volumes_loaded)} MRI volumes")

# Load the AI segmentation as a segmentation node
if os.path.exists(seg_path):
    # Load as labelmap first, then convert to segmentation
    labelmap_node = slicer.util.loadLabelVolume(seg_path)
    if labelmap_node:
        labelmap_node.SetName("AI_Segmentation_LabelMap")
        
        # Create segmentation from labelmap
        seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
        seg_node.SetName("AI_Tumor_Segmentation")
        
        # Import labelmap into segmentation
        slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmap_node, seg_node)
        
        # Remove the temporary labelmap
        slicer.mrmlScene.RemoveNode(labelmap_node)
        
        # Set segment color and name
        segmentation = seg_node.GetSegmentation()
        for i in range(segmentation.GetNumberOfSegments()):
            segment = segmentation.GetNthSegment(i)
            segment.SetName(f"Tumor_Region_{i+1}")
            segment.SetColor(1.0, 0.0, 0.0)  # Red
        
        print("Loaded AI segmentation for review")
        
        # Show segmentation in slice views
        seg_node.CreateClosedSurfaceRepresentation()
        displayNode = seg_node.GetDisplayNode()
        if displayNode:
            displayNode.SetVisibility(True)
            displayNode.SetOpacity2DFill(0.3)
            displayNode.SetOpacity2DOutline(1.0)

# Set FLAIR as background (best for tumor visualization)
flair_node = slicer.util.getNode("FLAIR")
if flair_node:
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceCompositeNode = sliceWidget.mrmlSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

# Reset slice views
slicer.util.resetSliceViews()

# Switch to Segment Editor module
slicer.util.selectModule("SegmentEditor")

print("")
print("=== QC TASK READY ===")
print("The AI segmentation has known errors. Review and correct them.")
print("Use Segment Editor tools: Paint, Erase, Smoothing")
print("Save corrected segmentation to: ~/Documents/SlicerData/BraTS/corrected_segmentation.nii.gz")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the QC data
echo "Launching 3D Slicer with QC data..."
sudo -u ga DISPLAY=:1 SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/load_qc_data.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
fi

# Wait for data to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/qc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Segmentation QC and Correction"
echo "======================================"
echo ""
echo "An AI has segmented this brain tumor but made errors:"
echo "  1. Under-segmentation: Part of the tumor edge was missed"
echo "  2. Over-segmentation: False positive region outside tumor"
echo "  3. Boundary roughening: Jagged edges in some areas"
echo ""
echo "Your task:"
echo "  1. Review the segmentation against FLAIR and T1_Contrast images"
echo "  2. Use Segment Editor to fix the errors"
echo "  3. Save to: ~/Documents/SlicerData/BraTS/corrected_segmentation.nii.gz"
echo "  4. Create QC report: ~/Documents/SlicerData/BraTS/qc_report.json"
echo ""