#!/bin/bash
echo "=== Setting up Segmentation QC Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# First ensure BraTS data is prepared
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
BROKEN_SEG="$BRATS_DIR/ai_segmentation.nii.gz"

echo "Using sample: $SAMPLE_ID"

# Verify MRI volumes exist
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

# Create the broken segmentation (if not exists)
echo "Creating broken AI segmentation..."
export GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
export OUTPUT_BROKEN="$BROKEN_SEG"
export GROUND_TRUTH_DIR
export SAMPLE_ID
/workspace/scripts/create_broken_segmentation.sh

# Verify broken segmentation exists
if [ ! -f "$BROKEN_SEG" ]; then
    echo "ERROR: Broken segmentation not found at $BROKEN_SEG"
    exit 1
fi
echo "Broken AI segmentation verified"

# Verify ground truth and error info exist
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_broken_errors.json" ]; then
    echo "ERROR: Error info not found!"
    exit 1
fi
echo "Ground truth and error info verified (hidden from agent)"

# Record initial state
rm -f /tmp/qc_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/corrected_segmentation.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/qc_report.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create a Slicer Python script to load MRI + broken segmentation overlay
cat > /tmp/load_qc_data.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"
broken_seg_path = "$BROKEN_SEG"

# Load MRI volumes
volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("Loading BraTS MRI volumes...")
loaded_volumes = []
for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_volumes.append(node)
            print(f"    Loaded: {node.GetName()}")

print(f"Loaded {len(loaded_volumes)} MRI volumes")

# Load the broken AI segmentation as a segmentation node
print(f"Loading AI segmentation from {broken_seg_path}...")
if os.path.exists(broken_seg_path):
    # Load as labelmap first
    labelmap_node = slicer.util.loadLabelVolume(broken_seg_path)
    if labelmap_node:
        labelmap_node.SetName("AI_Segmentation")
        print("  Loaded AI segmentation as label map")

        # Convert labelmap to segmentation for editing in Segment Editor
        seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
        seg_node.SetName("TumorSegmentation")

        slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(
            labelmap_node, seg_node)

        # Set segment names and colors
        segmentation = seg_node.GetSegmentation()
        segment_names = {
            "1": ("Necrotic_Core", (0.8, 0.2, 0.2)),
            "2": ("Edema", (0.2, 0.8, 0.2)),
            "4": ("Enhancing_Tumor", (0.2, 0.2, 0.8)),
        }
        for i in range(segmentation.GetNumberOfSegments()):
            segment = segmentation.GetNthSegment(i)
            label_value = segment.GetName()
            if label_value in segment_names:
                name, color = segment_names[label_value]
                segment.SetName(name)
                segment.SetColor(*color)

        # Remove the temporary labelmap node
        slicer.mrmlScene.RemoveNode(labelmap_node)

        # Make segmentation visible as overlay
        seg_node.CreateDefaultDisplayNodes()
        displayNode = seg_node.GetDisplayNode()
        if displayNode:
            displayNode.SetVisibility(True)
            displayNode.SetOpacity2DFill(0.3)
            displayNode.SetOpacity2DOutline(1.0)

        print("  Segmentation ready for editing in Segment Editor")
    else:
        print("  WARNING: Could not load AI segmentation")
else:
    print(f"  WARNING: Broken segmentation file not found: {broken_seg_path}")

# Set up views
if loaded_volumes:
    flair_node = None
    for node in loaded_volumes:
        if "FLAIR" in node.GetName():
            flair_node = node
            break
    if not flair_node:
        flair_node = loaded_volumes[0]

    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

    slicer.util.resetSliceViews()

    # Center on data
    bounds = [0]*6
    flair_node.GetBounds(bounds)
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

print("Setup complete - ready for segmentation QC task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with MRI + AI segmentation..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_qc_data.py > /tmp/slicer_launch.log 2>&1 &

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

# Take initial screenshot
take_screenshot /tmp/qc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Segmentation Quality Control (Find & Fix Errors)"
echo "======================================================="
echo ""
echo "You are given a brain MRI scan with a pre-existing AI tumor"
echo "segmentation (shown as a colored overlay). The segmentation"
echo "may contain errors."
echo ""
echo "Your goal:"
echo "  1. Review how well the segmentation overlaps with visible tumor"
echo "  2. Identify errors:"
echo "     - Under-segmentation (tumor present but not segmented)"
echo "     - Over-segmentation (marked as tumor but isn't)"
echo "     - Boundary inaccuracies"
echo "  3. Correct all errors using the Segment Editor"
echo "  4. Report what errors you found and corrections you made"
echo ""
echo "Save your outputs:"
echo "  - Corrected segmentation: ~/Documents/SlicerData/BraTS/corrected_segmentation.nii.gz"
echo "  - QC Report: ~/Documents/SlicerData/BraTS/qc_report.json"
echo ""
