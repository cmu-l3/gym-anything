#!/bin/bash
echo "=== Setting up Invert Brain Mask Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
DATA_DIR="/home/ga/Documents/SlicerData"

mkdir -p "$DATA_DIR"
mkdir -p "$SAMPLE_DIR"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    wget -q -O "$SAMPLE_FILE" "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    curl -L -o "$SAMPLE_FILE" "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
        echo "Warning: Could not download sample data"
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: Sample file not available at $SAMPLE_FILE"
    exit 1
fi

echo "Sample file: $SAMPLE_FILE"

# Clean up any previous task state
rm -f /tmp/invert_mask_result.json 2>/dev/null || true
rm -f /tmp/initial_segmentation_state.json 2>/dev/null || true
rm -f "$DATA_DIR/invert_task_segmentation.seg.nrrd" 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load data and create initial brain segmentation
SETUP_SCRIPT="/tmp/setup_brain_segmentation.py"
cat > "$SETUP_SCRIPT" << 'PYEOF'
import slicer
import os
import json
import time

print("=== Setting up brain segmentation ===")

# Load the MRHead volume
sample_file = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
print(f"Loading volume: {sample_file}")

volumeNode = slicer.util.loadVolume(sample_file)
if not volumeNode:
    print("ERROR: Failed to load volume")
    exit(1)

print(f"Volume loaded: {volumeNode.GetName()}")

# Get volume dimensions for reference
imageData = volumeNode.GetImageData()
dims = imageData.GetDimensions()
total_voxels = dims[0] * dims[1] * dims[2]
print(f"Volume dimensions: {dims}, total voxels: {total_voxels}")

# Create segmentation node
segmentationNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
segmentationNode.SetName("BrainSegmentation")
segmentationNode.CreateDefaultDisplayNodes()
segmentationNode.SetReferenceImageGeometryParameterFromVolumeNode(volumeNode)

# Create "Brain" segment
brainSegmentId = segmentationNode.GetSegmentation().AddEmptySegment("Brain")
brainSegment = segmentationNode.GetSegmentation().GetSegment(brainSegmentId)
brainSegment.SetColor(0.9, 0.3, 0.3)  # Red color

print("Created Brain segment, applying threshold...")

# Use Segment Editor to threshold the brain
segmentEditorWidget = slicer.qMRMLSegmentEditorWidget()
segmentEditorWidget.setMRMLScene(slicer.mrmlScene)
segmentEditorNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentEditorNode")
segmentEditorWidget.setMRMLSegmentEditorNode(segmentEditorNode)
segmentEditorWidget.setSegmentationNode(segmentationNode)
segmentEditorWidget.setSourceVolumeNode(volumeNode)
segmentEditorWidget.setCurrentSegmentID(brainSegmentId)

# Apply threshold effect to segment brain tissue
# MRHead intensity range: brain tissue typically 100-500
segmentEditorWidget.setActiveEffectByName("Threshold")
effect = segmentEditorWidget.activeEffect()
if effect:
    effect.setParameter("MinimumThreshold", "80")
    effect.setParameter("MaximumThreshold", "500")
    effect.self().onApply()
    print("Threshold applied (80-500)")

# Apply morphological smoothing to clean up
segmentEditorWidget.setActiveEffectByName("Smoothing")
effect = segmentEditorWidget.activeEffect()
if effect:
    effect.setParameter("SmoothingMethod", "MORPHOLOGICAL_CLOSING")
    effect.setParameter("KernelSizeMm", "3.0")
    effect.self().onApply()
    print("Morphological closing applied")

# Apply islands effect to keep largest island (remove noise)
segmentEditorWidget.setActiveEffectByName("Islands")
effect = segmentEditorWidget.activeEffect()
if effect:
    effect.setParameter("Operation", "KEEP_LARGEST_ISLAND")
    effect.self().onApply()
    print("Kept largest island")

# Get brain segment statistics
import numpy as np
segmentIds = vtk.vtkStringArray()
segmentationNode.GetSegmentation().GetSegmentIDs(segmentIds)

labelmapVolumeNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
slicer.modules.segmentations.logic().ExportVisibleSegmentsToLabelmapNode(
    segmentationNode, labelmapVolumeNode, volumeNode)

labelmapArray = slicer.util.arrayFromVolume(labelmapVolumeNode)
brain_voxels = int(np.sum(labelmapArray > 0))

slicer.mrmlScene.RemoveNode(labelmapVolumeNode)

print(f"Brain segment voxels: {brain_voxels}")

# Save initial state for verification
initial_state = {
    "volume_name": volumeNode.GetName(),
    "volume_dimensions": list(dims),
    "total_voxels": total_voxels,
    "segmentation_name": segmentationNode.GetName(),
    "brain_segment_id": brainSegmentId,
    "brain_voxels": brain_voxels,
    "segments_count": 1,
    "segment_names": ["Brain"],
    "timestamp": time.time()
}

with open("/tmp/initial_segmentation_state.json", "w") as f:
    json.dump(initial_state, f, indent=2)

print(f"Initial state saved: {initial_state}")

# Switch to Segment Editor module
slicer.util.selectModule("SegmentEditor")

# Center the views on the data
slicer.util.resetSliceViews()

# Set a good viewing angle
layoutManager = slicer.app.layoutManager()
for viewName in ["Red", "Green", "Yellow"]:
    sliceWidget = layoutManager.sliceWidget(viewName)
    if sliceWidget:
        sliceWidget.sliceController().fitSliceToBackground()

print("=== Setup complete ===")
print("Task: Create an inverse segment named 'NonBrain' using Logical operators")
PYEOF

chmod 644 "$SETUP_SCRIPT"
chown ga:ga "$SETUP_SCRIPT"

# Launch Slicer and run setup script
echo "Launching 3D Slicer with setup script..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script '$SETUP_SCRIPT' > /tmp/slicer_setup.log 2>&1 &"

# Wait for Slicer to start and setup to complete
echo "Waiting for Slicer to initialize..."
sleep 10

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for setup script to finish (check for state file)
echo "Waiting for segmentation setup to complete..."
for i in {1..30}; do
    if [ -f /tmp/initial_segmentation_state.json ]; then
        echo "Setup script completed"
        break
    fi
    sleep 2
done

# Verify setup completed
if [ ! -f /tmp/initial_segmentation_state.json ]; then
    echo "WARNING: Setup script may not have completed"
else
    echo "Initial state:"
    cat /tmp/initial_segmentation_state.json
fi

# Maximize and focus Slicer
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo "Starting state:"
echo "  - MRHead brain MRI loaded"
echo "  - 'Brain' segment created (shown in red)"
echo "  - Segment Editor module active"
echo ""
echo "YOUR TASK: Create inverse segment 'NonBrain' using Logical operators"
echo "  1. Add new segment named 'NonBrain'"
echo "  2. Use Logical operators effect"
echo "  3. Apply 'Invert' with Brain as modifier"