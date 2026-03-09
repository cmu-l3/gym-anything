#!/bin/bash
echo "=== Setting up Create Hollow Shell Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded"

# Ensure directories exist
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean previous task results
rm -f /tmp/hollow_shell_result.json 2>/dev/null || true
rm -f /tmp/original_liver_volume.txt 2>/dev/null || true
rm -f /tmp/segment_modified_time.txt 2>/dev/null || true

# Prepare IRCADb data (downloads real data if not exists)
echo "Preparing IRCADb liver CT data..."
export PATIENT_NUM GROUND_TRUTH_DIR IRCADB_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
echo "Using patient: $PATIENT_NUM"
echo "Patient directory: $PATIENT_DIR"

# Verify data exists
if [ ! -d "$PATIENT_DIR" ]; then
    echo "ERROR: Patient data directory not found at $PATIENT_DIR"
    exit 1
fi

# Get the ground truth segmentation with liver
GT_SEG="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_seg.nii.gz"
if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi

echo "Ground truth segmentation: $GT_SEG"

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load data and create liver segment
echo "Creating setup script for Slicer..."
cat > /tmp/setup_hollow_task.py << 'PYEOF'
import slicer
import os
import json

print("=== Setting up Hollow Shell Task in Slicer ===")

patient_dir = os.environ.get("PATIENT_DIR", "/home/ga/Documents/SlicerData/IRCADb/patient_5")
gt_seg_path = os.environ.get("GT_SEG", "/var/lib/slicer/ground_truth/ircadb_patient5_seg.nii.gz")

# Find DICOM directory
dicom_dir = os.path.join(patient_dir, "PATIENT_DICOM")
if not os.path.isdir(dicom_dir):
    # Try finding DICOM files directly in patient directory
    for root, dirs, files in os.walk(patient_dir):
        if any(f.endswith('.dcm') or f.isdigit() for f in files):
            dicom_dir = root
            break

print(f"DICOM directory: {dicom_dir}")

# Load DICOM data
if os.path.isdir(dicom_dir):
    print("Loading DICOM series...")
    dicomDataDir = dicom_dir
    from DICOMLib import DICOMUtils
    loadedNodeIDs = []
    
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicomDataDir, db)
        patientUIDs = db.patients()
        for patientUID in patientUIDs:
            loadedNodeIDs.extend(DICOMUtils.loadPatientByUID(patientUID))
    
    if loadedNodeIDs:
        print(f"Loaded {len(loadedNodeIDs)} node(s) from DICOM")
    else:
        print("Warning: No nodes loaded from DICOM")

# Load ground truth segmentation as labelmap
print(f"Loading liver segmentation from: {gt_seg_path}")
if os.path.exists(gt_seg_path):
    labelmapNode = slicer.util.loadLabelVolume(gt_seg_path, {"name": "LiverLabelmap"})
    print(f"Loaded labelmap: {labelmapNode.GetName()}")
    
    # Create segmentation from labelmap
    segmentationNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode", "LiverSegmentation")
    
    # Import labelmap to segmentation
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segmentationNode)
    
    # Rename the liver segment (label 1 in IRCADb is liver)
    segmentation = segmentationNode.GetSegmentation()
    num_segments = segmentation.GetNumberOfSegments()
    print(f"Created segmentation with {num_segments} segment(s)")
    
    # Find and rename liver segment
    for i in range(num_segments):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        segment_name = segment.GetName()
        print(f"  Segment {i}: {segment_name} (ID: {segment_id})")
        
        # Rename to "Liver" for clarity (segment 1 is typically liver in IRCADb)
        if "1" in segment_name or "liver" in segment_name.lower():
            segment.SetName("Liver")
            print(f"  Renamed to 'Liver'")
    
    # Calculate and save original liver volume
    import SegmentStatistics
    segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
    segStatLogic.getParameterNode().SetParameter("Segmentation", segmentationNode.GetID())
    segStatLogic.computeStatistics()
    stats = segStatLogic.getStatistics()
    
    # Find liver segment stats
    liver_volume_mm3 = 0
    for segment_id in stats["SegmentIDs"]:
        segment = segmentation.GetSegment(segment_id)
        if segment and "Liver" in segment.GetName():
            vol_key = f"{segment_id},LabelmapSegmentStatisticsPlugin.volume_mm3"
            if vol_key in stats:
                liver_volume_mm3 = stats[vol_key]
                break
    
    liver_volume_ml = liver_volume_mm3 / 1000.0
    print(f"Original liver volume: {liver_volume_ml:.2f} mL")
    
    # Save original volume for verification
    with open("/tmp/original_liver_volume.txt", "w") as f:
        f.write(f"{liver_volume_ml:.4f}")
    
    # Save setup info
    setup_info = {
        "patient_num": os.environ.get("PATIENT_NUM", "5"),
        "original_volume_ml": liver_volume_ml,
        "original_volume_mm3": liver_volume_mm3,
        "num_segments": num_segments,
        "segmentation_node_id": segmentationNode.GetID()
    }
    with open("/tmp/hollow_setup_info.json", "w") as f:
        json.dump(setup_info, f, indent=2)
    
    # Remove the labelmap node (we only need the segmentation)
    slicer.mrmlScene.RemoveNode(labelmapNode)
    
    # Show segmentation in 3D view
    segmentationNode.CreateClosedSurfaceRepresentation()
    
    # Set up display
    displayNode = segmentationNode.GetDisplayNode()
    if displayNode:
        displayNode.SetVisibility(True)
        displayNode.SetVisibility3D(True)
    
    # Switch to Segment Editor module
    slicer.util.selectModule("SegmentEditor")
    
    # Set the segmentation as active in Segment Editor
    segmentEditorWidget = slicer.modules.segmenteditor.widgetRepresentation().self().editor
    segmentEditorWidget.setSegmentationNode(segmentationNode)
    
    # Select the Liver segment
    for i in range(segmentation.GetNumberOfSegments()):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        if segment and "Liver" in segment.GetName():
            segmentEditorWidget.setCurrentSegmentID(segment_id)
            print(f"Selected segment: {segment.GetName()}")
            break

else:
    print(f"ERROR: Ground truth file not found: {gt_seg_path}")

# Reset 3D view to show the liver
layoutManager = slicer.app.layoutManager()
threeDWidget = layoutManager.threeDWidget(0)
threeDView = threeDWidget.threeDView()
threeDView.resetFocalPoint()
threeDView.resetCamera()

print("=== Setup complete ===")
print("The Liver segment is loaded and selected in Segment Editor.")
print("Use the 'Hollow' effect with 3mm thickness to create a shell.")
PYEOF

# Export environment variables for Python script
export PATIENT_DIR
export GT_SEG
export PATIENT_NUM

# Launch Slicer with setup script
echo "Launching 3D Slicer with liver data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/setup_hollow_task.py > /tmp/slicer_setup.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 15

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for setup script to complete (check for setup info file)
echo "Waiting for data to load..."
for i in {1..30}; do
    if [ -f /tmp/hollow_setup_info.json ]; then
        echo "Setup completed successfully"
        cat /tmp/hollow_setup_info.json
        break
    fi
    sleep 2
done

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Record initial liver volume
if [ -f /tmp/original_liver_volume.txt ]; then
    ORIGINAL_VOLUME=$(cat /tmp/original_liver_volume.txt)
    echo "Original liver volume: ${ORIGINAL_VOLUME} mL"
else
    echo "WARNING: Original volume not recorded"
fi

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a hollow shell of the liver segment for 3D printing optimization"
echo ""
echo "Instructions:"
echo "1. The Liver segment is already loaded and selected in Segment Editor"
echo "2. Find the 'Hollow' effect in the effects palette (scroll down if needed)"
echo "3. Set shell thickness to 3.0 mm"
echo "4. Choose 'Inside surface' mode"
echo "5. Click 'Apply' to create the hollow shell"
echo ""
echo "Expected result: Volume should decrease by ~40-60%"