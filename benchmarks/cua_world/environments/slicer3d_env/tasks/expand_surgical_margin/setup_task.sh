#!/bin/bash
echo "=== Setting up Expand Surgical Margin Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SAMPLE_ID="BraTS2021_00000"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean previous results
rm -f "$BRATS_DIR/surgical_margin_segmentation.seg.nrrd" 2>/dev/null || true
rm -f /tmp/margin_task_result.json 2>/dev/null || true

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
/workspace/scripts/prepare_brats_data.sh "$SAMPLE_ID"

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"
echo "Case directory: $CASE_DIR"

# Verify data exists
T1CE_FILE="$CASE_DIR/${SAMPLE_ID}_t1ce.nii.gz"
if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    ls -la "$CASE_DIR" 2>/dev/null || echo "Case directory not found"
    exit 1
fi

# Create initial segmentation from ground truth for the agent to use
echo "Creating initial tumor segmentation for agent..."

# The ground truth is in the hidden directory - we need to create a visible segmentation
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
INITIAL_SEG="$BRATS_DIR/initial_tumor_segmentation.seg.nrrd"

if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found"
    exit 1
fi

# Create initial segmentation (enhancing tumor only - label 4 in BraTS)
python3 << PYEOF
import os
import sys
import json

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    import nrrd
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"])
    import nrrd

gt_path = "$GT_SEG"
output_path = "$INITIAL_SEG"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

print(f"Loading ground truth from {gt_path}")
gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Extract only enhancing tumor (label 4) for the margin task
enhancing_mask = (gt_data == 4).astype(np.uint8)

# If no enhancing tumor, use all tumor
if np.sum(enhancing_mask) < 100:
    print("Warning: Very few enhancing tumor voxels, using all tumor labels")
    enhancing_mask = (gt_data > 0).astype(np.uint8)

print(f"Enhancing tumor voxels: {np.sum(enhancing_mask)}")

# Calculate initial volume
voxel_volume_mm3 = float(np.prod(voxel_dims))
initial_volume_mm3 = float(np.sum(enhancing_mask)) * voxel_volume_mm3
initial_volume_ml = initial_volume_mm3 / 1000.0

print(f"Initial tumor volume: {initial_volume_ml:.2f} mL")

# Save as NRRD for Slicer (Slicer prefers NRRD for segmentations)
# Create header with proper spacing
header = {
    'type': 'uint8',
    'dimension': 3,
    'space': 'left-posterior-superior',
    'sizes': list(enhancing_mask.shape),
    'space directions': [
        [voxel_dims[0], 0, 0],
        [0, voxel_dims[1], 0],
        [0, 0, voxel_dims[2]]
    ],
    'kinds': ['domain', 'domain', 'domain'],
    'encoding': 'gzip',
    'space origin': [0, 0, 0]
}

nrrd.write(output_path, enhancing_mask, header)
print(f"Initial segmentation saved to {output_path}")

# Save ground truth metrics for verification
gt_metrics = {
    "sample_id": sample_id,
    "initial_volume_mm3": initial_volume_mm3,
    "initial_volume_ml": initial_volume_ml,
    "initial_voxel_count": int(np.sum(enhancing_mask)),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_mm3": voxel_volume_mm3,
    "shape": list(enhancing_mask.shape),
    "margin_size_mm": 5.0
}

# Calculate expected expanded volume (rough spherical approximation)
# For a sphere: V_new/V_old = ((r+margin)/r)^3
# Estimate equivalent radius from volume
equiv_radius = (3 * initial_volume_mm3 / (4 * 3.14159)) ** (1/3)
expected_ratio = ((equiv_radius + 5.0) / equiv_radius) ** 3 if equiv_radius > 0 else 2.0
gt_metrics["estimated_equiv_radius_mm"] = float(equiv_radius)
gt_metrics["expected_volume_ratio_spherical"] = float(expected_ratio)

# Save metrics for verifier
metrics_path = os.path.join(gt_dir, f"{sample_id}_margin_metrics.json")
with open(metrics_path, 'w') as f:
    json.dump(gt_metrics, f, indent=2)

print(f"Ground truth metrics saved to {metrics_path}")
print(f"  Initial volume: {initial_volume_ml:.2f} mL")
print(f"  Equivalent radius: {equiv_radius:.1f} mm")
print(f"  Expected volume ratio for 5mm margin: {expected_ratio:.2f}x")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create initial segmentation"
    exit 1
fi

# Verify initial segmentation exists
if [ ! -f "$INITIAL_SEG" ]; then
    echo "ERROR: Initial segmentation not created"
    exit 1
fi
echo "Initial segmentation created: $INITIAL_SEG"

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load data and segmentation in Slicer
LOAD_SCRIPT="/tmp/load_margin_task.py"
cat > "$LOAD_SCRIPT" << 'PYEOF'
import slicer
import os
import time

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
case_dir = os.path.join(brats_dir, sample_id)

print("Loading BraTS data for surgical margin task...")

# Load T1ce volume (contrast-enhanced, best for seeing tumor)
t1ce_path = os.path.join(case_dir, f"{sample_id}_t1ce.nii.gz")
if os.path.exists(t1ce_path):
    print(f"Loading T1ce: {t1ce_path}")
    t1ce_node = slicer.util.loadVolume(t1ce_path)
    t1ce_node.SetName("T1ce")
    
    # Set as background in all slice views
    for color in ['Red', 'Yellow', 'Green']:
        sliceLogic = slicer.app.layoutManager().sliceWidget(color).sliceLogic()
        sliceLogic.GetSliceCompositeNode().SetBackgroundVolumeID(t1ce_node.GetID())
else:
    print(f"WARNING: T1ce not found at {t1ce_path}")

# Load initial tumor segmentation
seg_path = os.path.join(brats_dir, "initial_tumor_segmentation.seg.nrrd")
if os.path.exists(seg_path):
    print(f"Loading initial segmentation: {seg_path}")
    
    # Load as labelmap first, then convert to segmentation
    labelmapNode = slicer.util.loadLabelVolume(seg_path)
    labelmapNode.SetName("InitialTumorLabelmap")
    
    # Create segmentation node
    segNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    segNode.SetName("TumorSegmentation")
    
    # Import labelmap to segmentation
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segNode)
    
    # Rename the segment
    segmentation = segNode.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segmentId = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segmentId)
        segment.SetName("EnhancingTumor")
        # Set a visible color (red)
        segment.SetColor(1.0, 0.2, 0.2)
    
    # Show segmentation in 2D views
    segNode.CreateClosedSurfaceRepresentation()
    displayNode = segNode.GetDisplayNode()
    if displayNode:
        displayNode.SetVisibility(True)
        displayNode.SetVisibility2DFill(True)
        displayNode.SetVisibility2DOutline(True)
        displayNode.SetOpacity2DFill(0.3)
    
    # Remove the intermediate labelmap
    slicer.mrmlScene.RemoveNode(labelmapNode)
    
    print("Segmentation loaded and configured")
else:
    print(f"WARNING: Initial segmentation not found at {seg_path}")

# Center 3D view on the tumor
slicer.util.resetSliceViews()

# Switch to Segment Editor module
slicer.util.selectModule("SegmentEditor")

print("Setup complete - ready for margin expansion task")
PYEOF

export SAMPLE_ID BRATS_DIR
chmod 644 "$LOAD_SCRIPT"

# Launch Slicer with the setup script
echo "Launching 3D Slicer with BraTS data and segmentation..."
su - ga -c "DISPLAY=:1 SAMPLE_ID='$SAMPLE_ID' BRATS_DIR='$BRATS_DIR' /opt/Slicer/Slicer --python-script '$LOAD_SCRIPT' > /tmp/slicer_margin_launch.log 2>&1 &"

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start and load data..."
sleep 15

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data to fully load
sleep 10

# Maximize and focus
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
take_screenshot /tmp/margin_task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "Initial segmentation: $INITIAL_SEG"
echo "Expected output: $BRATS_DIR/surgical_margin_segmentation.seg.nrrd"
echo ""
echo "TASK: Use Segment Editor to expand 'EnhancingTumor' by 5mm using the Margin effect,"
echo "      then save the result to surgical_margin_segmentation.seg.nrrd"