#!/bin/bash
echo "=== Setting up Export STL for 3D Printing Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# PREPARE DIRECTORIES AND CLEAN STATE
# ============================================================
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPECTED_OUTPUT="$EXPORT_DIR/tumor_model.stl"

mkdir -p "$BRATS_DIR"
mkdir -p "$EXPORT_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Set permissions
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true
chmod 755 "$EXPORT_DIR" 2>/dev/null || true

# Remove any existing output (clean slate for anti-gaming)
rm -f "$EXPECTED_OUTPUT" 2>/dev/null || true
rm -f "$EXPORT_DIR"/*.stl 2>/dev/null || true

# Record initial file state
echo "0" > /tmp/initial_stl_count.txt
ls -1 "$EXPORT_DIR"/*.stl 2>/dev/null | wc -l > /tmp/initial_stl_count.txt || echo "0" > /tmp/initial_stl_count.txt

# ============================================================
# PREPARE BRATS DATA
# ============================================================
echo "Preparing BraTS brain tumor data..."

# Check if BraTS data preparation script exists
if [ -f /workspace/scripts/prepare_brats_data.sh ]; then
    /workspace/scripts/prepare_brats_data.sh
else
    echo "WARNING: BraTS preparation script not found, using fallback method"
fi

# Get the sample ID
SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
echo "Using sample ID: $SAMPLE_ID"

# Verify data exists
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

if [ ! -f "$FLAIR_FILE" ]; then
    echo "WARNING: FLAIR file not found at $FLAIR_FILE"
    # Try to find any nii.gz file
    FLAIR_FILE=$(find "$BRATS_DIR" -name "*flair*.nii.gz" 2>/dev/null | head -1)
fi

if [ ! -f "$GT_SEG" ]; then
    echo "WARNING: Ground truth segmentation not found at $GT_SEG"
    GT_SEG=$(find "$GROUND_TRUTH_DIR" -name "*seg*.nii.gz" 2>/dev/null | head -1)
fi

echo "FLAIR file: $FLAIR_FILE"
echo "Ground truth segmentation: $GT_SEG"

# ============================================================
# CREATE SLICER SETUP SCRIPT
# ============================================================
SETUP_SCRIPT="/tmp/setup_stl_export_task.py"
cat > "$SETUP_SCRIPT" << 'PYEOF'
import slicer
import os
import sys

# Get environment variables
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

print(f"Setting up scene with sample: {sample_id}")
print(f"BraTS directory: {brats_dir}")
print(f"Ground truth directory: {gt_dir}")

# Clear existing scene
slicer.mrmlScene.Clear(0)

# Find and load the FLAIR volume
flair_path = os.path.join(brats_dir, sample_id, f"{sample_id}_flair.nii.gz")
if not os.path.exists(flair_path):
    # Try to find any flair file
    import glob
    flair_files = glob.glob(os.path.join(brats_dir, "**/*flair*.nii.gz"), recursive=True)
    if flair_files:
        flair_path = flair_files[0]
        print(f"Using fallback FLAIR: {flair_path}")

if os.path.exists(flair_path):
    print(f"Loading FLAIR: {flair_path}")
    volumeNode = slicer.util.loadVolume(flair_path)
    if volumeNode:
        print(f"FLAIR loaded successfully: {volumeNode.GetName()}")
else:
    print(f"ERROR: FLAIR not found at {flair_path}")

# Find and load the ground truth segmentation
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
if not os.path.exists(seg_path):
    # Try to find any seg file
    import glob
    seg_files = glob.glob(os.path.join(gt_dir, "*seg*.nii.gz"))
    if seg_files:
        seg_path = seg_files[0]
        print(f"Using fallback segmentation: {seg_path}")

if os.path.exists(seg_path):
    print(f"Loading segmentation: {seg_path}")
    
    # Load as labelmap first
    labelmapNode = slicer.util.loadLabelVolume(seg_path)
    if labelmapNode:
        print(f"Labelmap loaded: {labelmapNode.GetName()}")
        
        # Create segmentation node
        segmentationNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
        segmentationNode.SetName("TumorSegmentation")
        
        # Import labelmap into segmentation
        slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segmentationNode)
        
        # Get the segmentation
        segmentation = segmentationNode.GetSegmentation()
        numSegments = segmentation.GetNumberOfSegments()
        print(f"Created TumorSegmentation with {numSegments} segment(s)")
        
        # Rename segments for clarity
        for i in range(numSegments):
            segmentID = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segmentID)
            oldName = segment.GetName()
            if i == 0:
                segment.SetName("Tumor_Necrotic")
            elif i == 1:
                segment.SetName("Tumor_Edema")
            elif i == 2:
                segment.SetName("Tumor_Enhancing")
            else:
                segment.SetName(f"Tumor_Region_{i}")
            print(f"  Segment {i}: {oldName} -> {segment.GetName()}")
        
        # Create closed surface representation for 3D visualization
        segmentationNode.CreateClosedSurfaceRepresentation()
        print("Created closed surface representation")
        
        # Remove temporary labelmap
        slicer.mrmlScene.RemoveNode(labelmapNode)
        
        # Make segmentation visible
        displayNode = segmentationNode.GetDisplayNode()
        if displayNode:
            displayNode.SetVisibility(True)
            displayNode.SetVisibility3D(True)
            displayNode.SetVisibility2D(True)
else:
    print(f"ERROR: Segmentation not found at {seg_path}")

# Set up views
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Reset 3D view to show the segmentation
threeDWidget = layoutManager.threeDWidget(0)
if threeDWidget:
    threeDView = threeDWidget.threeDView()
    threeDView.resetFocalPoint()
    threeDView.resetCamera()

# Print scene summary
print("\n=== Scene Summary ===")
volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Volume nodes: {len(volumeNodes)}")
for node in volumeNodes:
    print(f"  - {node.GetName()}")

segNodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Segmentation nodes: {len(segNodes)}")
for node in segNodes:
    seg = node.GetSegmentation()
    print(f"  - {node.GetName()} ({seg.GetNumberOfSegments()} segments)")

print("\n=== Setup complete - ready for STL export task ===")
print(f"Export target: /home/ga/Documents/SlicerData/Exports/tumor_model.stl")
PYEOF

chmod 644 "$SETUP_SCRIPT"
chown ga:ga "$SETUP_SCRIPT"

# ============================================================
# LAUNCH 3D SLICER WITH SETUP SCRIPT
# ============================================================
echo ""
echo "Launching 3D Slicer with scene setup..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Set environment variables for the setup script
export SAMPLE_ID
export BRATS_DIR
export GROUND_TRUTH_DIR
export DISPLAY=:1

# Allow X11 access
xhost +local: 2>/dev/null || true

# Launch Slicer as ga user with the setup script
echo "Running setup script in Slicer..."
sudo -u ga DISPLAY=:1 SAMPLE_ID="$SAMPLE_ID" BRATS_DIR="$BRATS_DIR" GROUND_TRUTH_DIR="$GROUND_TRUTH_DIR" \
    /opt/Slicer/Slicer --python-script "$SETUP_SCRIPT" > /tmp/slicer_setup.log 2>&1 &

SLICER_PID=$!
echo "Slicer launched with PID: $SLICER_PID"

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for scene to load
echo "Waiting for scene to load..."
sleep 15

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Save setup info for verification
cat > /tmp/stl_task_setup.json << EOF
{
    "sample_id": "$SAMPLE_ID",
    "flair_path": "$FLAIR_FILE",
    "segmentation_path": "$GT_SEG",
    "export_dir": "$EXPORT_DIR",
    "expected_output": "$EXPECTED_OUTPUT",
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "setup_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "Export directory: $EXPORT_DIR"
echo "Expected output: $EXPECTED_OUTPUT"
echo ""
echo "The agent should export TumorSegmentation as STL to:"
echo "  ~/Documents/SlicerData/Exports/tumor_model.stl"