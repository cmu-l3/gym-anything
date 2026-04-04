#!/bin/bash
echo "=== Setting up Surgical Planning View Configuration Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Prepare IRCADb data
echo "Preparing IRCADb liver CT data..."
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export PATIENT_NUM IRCADB_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM" || {
    echo "WARNING: IRCADb preparation had issues, continuing with available data..."
}

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

echo "Using patient: $PATIENT_NUM"

# Determine data paths
CT_FILE="$IRCADB_DIR/patient_${PATIENT_NUM}/ct_volume.nii.gz"
SEG_FILE="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_seg.nii.gz"

# Check for alternative paths if standard doesn't exist
if [ ! -f "$CT_FILE" ]; then
    CT_FILE=$(find "$IRCADB_DIR" -name "*.nii.gz" -type f 2>/dev/null | head -1)
fi
if [ ! -f "$SEG_FILE" ]; then
    SEG_FILE=$(find "$GROUND_TRUTH_DIR" -name "*seg*.nii.gz" -type f 2>/dev/null | head -1)
fi

echo "CT file: $CT_FILE"
echo "Segmentation file: $SEG_FILE"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load data and create segmentation with named segments
cat > /tmp/setup_surgical_view.py << 'PYEOF'
import slicer
import os
import json
import random

ircadb_dir = os.environ.get("IRCADB_DIR", "/home/ga/Documents/SlicerData/IRCADb")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_num = os.environ.get("PATIENT_NUM", "5")

# Find available data files
ct_file = None
seg_file = None

# Look for CT volume
for root, dirs, files in os.walk(ircadb_dir):
    for f in files:
        if f.endswith('.nii.gz') and 'seg' not in f.lower():
            ct_file = os.path.join(root, f)
            break
    if ct_file:
        break

# Look for segmentation
for f in os.listdir(gt_dir):
    if f.endswith('_seg.nii.gz'):
        seg_file = os.path.join(gt_dir, f)
        break

print(f"CT file: {ct_file}")
print(f"Segmentation file: {seg_file}")

# Load CT volume
if ct_file and os.path.exists(ct_file):
    print(f"Loading CT: {ct_file}")
    volumeNode = slicer.util.loadVolume(ct_file)
    volumeNode.SetName("LiverCT")
else:
    print("WARNING: No CT file found, creating empty volume")
    volumeNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLScalarVolumeNode", "LiverCT")

# Load or create segmentation with proper segment names
segmentationNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode", "LiverSegmentation")
segmentationNode.CreateDefaultDisplayNodes()

if seg_file and os.path.exists(seg_file):
    print(f"Loading segmentation labels: {seg_file}")
    labelmapNode = slicer.util.loadLabelVolume(seg_file)
    
    # Import labelmap into segmentation with proper names
    # IRCADb labels: 1=liver, 2=tumor, 3=portal vein (or similar)
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segmentationNode)
    slicer.mrmlScene.RemoveNode(labelmapNode)
    
    # Rename segments to standard names
    segmentation = segmentationNode.GetSegmentation()
    segment_names = ["Liver", "Tumor", "PortalVein"]
    for i in range(min(segmentation.GetNumberOfSegments(), len(segment_names))):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName(segment_names[i])
        print(f"  Renamed segment {i} to: {segment_names[i]}")
else:
    print("Creating synthetic segmentation for demonstration...")
    # Create synthetic segments if no data available
    import numpy as np
    
    # Create a simple labelmap
    shape = (100, 100, 50)
    labelmap = np.zeros(shape, dtype=np.int16)
    
    # Liver: large ellipsoid
    for x in range(shape[0]):
        for y in range(shape[1]):
            for z in range(shape[2]):
                # Liver
                if ((x-50)**2/30**2 + (y-50)**2/25**2 + (z-25)**2/15**2) < 1:
                    labelmap[x,y,z] = 1
                # Tumor (small sphere inside liver)
                if ((x-45)**2 + (y-45)**2 + (z-25)**2) < 8**2:
                    labelmap[x,y,z] = 2
                # Portal vein (cylinder)
                if ((x-60)**2 + (y-50)**2) < 4**2 and 10 < z < 40:
                    labelmap[x,y,z] = 3
    
    # Create labelmap node
    import vtk
    imageData = vtk.vtkImageData()
    imageData.SetDimensions(shape[0], shape[1], shape[2])
    imageData.AllocateScalars(vtk.VTK_SHORT, 1)
    
    for x in range(shape[0]):
        for y in range(shape[1]):
            for z in range(shape[2]):
                imageData.SetScalarComponentFromFloat(x, y, z, 0, float(labelmap[x,y,z]))
    
    labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode", "TempLabelmap")
    labelmapNode.SetAndObserveImageData(imageData)
    
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segmentationNode)
    slicer.mrmlScene.RemoveNode(labelmapNode)
    
    # Rename segments
    segmentation = segmentationNode.GetSegmentation()
    segment_names = ["Liver", "Tumor", "PortalVein"]
    for i in range(min(segmentation.GetNumberOfSegments(), len(segment_names))):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName(segment_names[i])

# Set RANDOM initial colors/opacities (so agent must change them)
displayNode = segmentationNode.GetDisplayNode()
segmentation = segmentationNode.GetSegmentation()

initial_properties = {}

# Randomize colors - NOT the target colors
random.seed(42)
for i in range(segmentation.GetNumberOfSegments()):
    segment_id = segmentation.GetNthSegmentID(i)
    segment = segmentation.GetSegment(segment_id)
    name = segment.GetName()
    
    # Set random initial colors (green, yellow, cyan - NOT the target colors)
    if name == "Liver":
        # Set to green initially (not tan/brown)
        segment.SetColor(0.2, 0.8, 0.2)
        displayNode.SetSegmentOpacity3D(segment_id, 0.8)  # Not 0.4
    elif name == "Tumor":
        # Set to yellow initially (not red)
        segment.SetColor(0.9, 0.9, 0.1)
        displayNode.SetSegmentOpacity3D(segment_id, 0.5)  # Not 1.0
    elif name == "PortalVein":
        # Set to cyan initially (not blue)
        segment.SetColor(0.1, 0.9, 0.9)
        displayNode.SetSegmentOpacity3D(segment_id, 0.6)  # Not 1.0
    
    # Record initial properties
    color = segment.GetColor()
    opacity = displayNode.GetSegmentOpacity3D(segment_id)
    initial_properties[name] = {
        "color_r": color[0],
        "color_g": color[1],
        "color_b": color[2],
        "opacity_3d": opacity,
        "visible": displayNode.GetSegmentVisibility(segment_id)
    }
    print(f"Initial {name}: color=({color[0]:.2f},{color[1]:.2f},{color[2]:.2f}), opacity={opacity:.2f}")

# Save initial properties for verification
with open("/tmp/initial_segment_properties.json", "w") as f:
    json.dump(initial_properties, f, indent=2)

# Enable 3D visibility for all segments
displayNode.SetAllSegmentsVisibility(True)
displayNode.SetVisibility(True)
displayNode.SetVisibility3D(True)

# Show 3D view
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Center 3D view on segmentation
threeDWidget = layoutManager.threeDWidget(0)
threeDView = threeDWidget.threeDView()
threeDView.resetFocalPoint()
threeDView.resetCamera()

# Navigate to Segment Editor module
slicer.util.selectModule("SegmentEditor")

print("Setup complete - segments loaded with initial (incorrect) colors")
print("Task: Configure correct surgical planning visualization colors/opacities")
PYEOF

# Export environment variables for Python script
export IRCADB_DIR GROUND_TRUTH_DIR PATIENT_NUM

# Launch Slicer and run setup script
echo "Launching 3D Slicer with segmentation data..."
su - ga -c "DISPLAY=:1 IRCADB_DIR='$IRCADB_DIR' GROUND_TRUTH_DIR='$GROUND_TRUTH_DIR' PATIENT_NUM='$PATIENT_NUM' /opt/Slicer/Slicer --python-script /tmp/setup_surgical_view.py > /tmp/slicer_setup.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for Slicer to initialize..."
wait_for_slicer 90

# Give extra time for segmentation to render
sleep 5

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
take_screenshot /tmp/surgical_view_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Patient: $PATIENT_NUM"
echo "Segments loaded: Liver, Tumor, PortalVein"
echo ""
echo "TASK: Configure the following display properties:"
echo "  - Liver: tan/brown color (~RGB 200,150,100), 40% opacity"
echo "  - Tumor: bright red (~RGB 255,0,0), 100% opacity"
echo "  - PortalVein: blue (~RGB 0,0,255), 100% opacity"
echo ""
echo "Access segment properties via Segment Editor or Data module."