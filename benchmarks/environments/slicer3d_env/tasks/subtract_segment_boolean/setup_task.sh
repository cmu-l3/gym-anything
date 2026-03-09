#!/bin/bash
set -e

echo "=== Setting up Segment Boolean Subtraction Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare BraTS data
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh 2>/dev/null || {
    echo "BraTS data preparation script not found or failed"
    echo "Creating synthetic BraTS-like data..."
    
    # Create synthetic data as fallback
    python3 << 'PYEOF'
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

brats_dir = "/home/ga/Documents/SlicerData/BraTS"
gt_dir = "/var/lib/slicer/ground_truth"
sample_id = "BraTS2021_00000"

os.makedirs(brats_dir, exist_ok=True)
os.makedirs(os.path.join(brats_dir, sample_id), exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

# Create synthetic brain volume with tumor
np.random.seed(42)
shape = (128, 128, 64)
affine = np.eye(4)
affine[0, 0] = 1.5
affine[1, 1] = 1.5
affine[2, 2] = 2.5

# Create FLAIR-like volume
flair = np.random.normal(500, 50, shape).astype(np.int16)

# Add "brain" structure
center = np.array(shape) // 2
Y, X, Z = np.ogrid[:shape[0], :shape[1], :shape[2]]
brain_mask = ((X - center[0])**2 / 50**2 + (Y - center[1])**2 / 50**2 + (Z - center[2])**2 / 25**2) <= 1.0
flair[brain_mask] = np.random.normal(800, 80, np.sum(brain_mask)).astype(np.int16)

# Add tumor region (brighter)
tumor_center = center + np.array([10, -5, 3])
tumor_mask = ((X - tumor_center[0])**2 + (Y - tumor_center[1])**2 + (Z - tumor_center[2])**2) <= 15**2
flair[tumor_mask] = np.random.normal(1100, 100, np.sum(tumor_mask)).astype(np.int16)

# Save FLAIR
flair_nii = nib.Nifti1Image(flair, affine)
flair_path = os.path.join(brats_dir, sample_id, f"{sample_id}_flair.nii.gz")
nib.save(flair_nii, flair_path)

# Create segmentation with labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
seg = np.zeros(shape, dtype=np.int16)

# Whole tumor (edema + enhancing + necrotic)
whole_tumor_mask = ((X - tumor_center[0])**2 + (Y - tumor_center[1])**2 + (Z - tumor_center[2])**2) <= 15**2
seg[whole_tumor_mask] = 2  # Edema

# Enhancing tumor (inner ring)
enhancing_mask = ((X - tumor_center[0])**2 + (Y - tumor_center[1])**2 + (Z - tumor_center[2])**2) <= 10**2
seg[enhancing_mask] = 4  # Enhancing

# Necrotic core (center)
necrotic_mask = ((X - tumor_center[0])**2 + (Y - tumor_center[1])**2 + (Z - tumor_center[2])**2) <= 5**2
seg[necrotic_mask] = 1  # Necrotic

# Save ground truth segmentation
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
seg_nii = nib.Nifti1Image(seg, affine)
nib.save(seg_nii, seg_path)

# Calculate statistics
voxel_volume_mm3 = 1.5 * 1.5 * 2.5
whole_tumor_voxels = int(np.sum(seg > 0))
necrotic_voxels = int(np.sum(seg == 1))
expected_viable_voxels = whole_tumor_voxels - necrotic_voxels

stats = {
    "sample_id": sample_id,
    "voxel_volume_mm3": voxel_volume_mm3,
    "whole_tumor_voxels": whole_tumor_voxels,
    "whole_tumor_volume_ml": round(whole_tumor_voxels * voxel_volume_mm3 / 1000.0, 3),
    "necrotic_voxels": necrotic_voxels,
    "necrotic_volume_ml": round(necrotic_voxels * voxel_volume_mm3 / 1000.0, 3),
    "expected_viable_voxels": expected_viable_voxels,
    "expected_viable_volume_ml": round(expected_viable_voxels * voxel_volume_mm3 / 1000.0, 3),
    "tolerance_percent": 5.0
}

stats_path = os.path.join(gt_dir, f"{sample_id}_boolean_gt.json")
with open(stats_path, 'w') as f:
    json.dump(stats, f, indent=2)

# Save sample ID
with open("/tmp/brats_sample_id", "w") as f:
    f.write(sample_id)

print(f"Created synthetic BraTS data for {sample_id}")
print(f"WholeTumor: {whole_tumor_voxels} voxels")
print(f"NecroticCore: {necrotic_voxels} voxels")
print(f"Expected after subtraction: {expected_viable_voxels} voxels")
PYEOF
}

# Get sample ID
SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
echo "Using BraTS case: $SAMPLE_ID"

# Create the initial segmentation with WholeTumor and NecroticCore segments
echo "Creating initial segmentation with two segments..."

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
gt_dir = "/var/lib/slicer/ground_truth"
brats_dir = "/home/ga/Documents/SlicerData/BraTS"
output_dir = brats_dir

# Load ground truth segmentation
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
print(f"Loading ground truth: {gt_seg_path}")

if not os.path.exists(gt_seg_path):
    print(f"ERROR: Ground truth not found at {gt_seg_path}")
    sys.exit(1)

seg_nii = nib.load(gt_seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
voxel_dims = seg_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Create WholeTumor: all tumor labels (1, 2, 4)
whole_tumor = (seg_data > 0).astype(np.int16)

# Create NecroticCore: only label 1
necrotic_core = (seg_data == 1).astype(np.int16)

# Create combined labelmap for Slicer import
# Label 1 = WholeTumor, Label 2 = NecroticCore (overlapping)
# We'll create separate files for each segment
combined = np.zeros_like(seg_data, dtype=np.int16)
combined[whole_tumor > 0] = 1
combined[necrotic_core > 0] = 2  # Overwrites necrotic region

# Save the initial segmentation labelmap
initial_seg_path = os.path.join(output_dir, f"{sample_id}_initial_seg.nii.gz")
combined_nii = nib.Nifti1Image(combined, affine, seg_nii.header)
nib.save(combined_nii, initial_seg_path)
print(f"Initial segmentation saved to: {initial_seg_path}")

# Calculate ground truth values for verification
whole_tumor_voxels = int(np.sum(whole_tumor))
necrotic_voxels = int(np.sum(necrotic_core))
expected_viable_voxels = whole_tumor_voxels - necrotic_voxels

whole_tumor_volume_ml = whole_tumor_voxels * voxel_volume_mm3 / 1000.0
necrotic_volume_ml = necrotic_voxels * voxel_volume_mm3 / 1000.0
expected_viable_volume_ml = expected_viable_voxels * voxel_volume_mm3 / 1000.0

# Save ground truth for verification
gt_data = {
    "sample_id": sample_id,
    "voxel_volume_mm3": voxel_volume_mm3,
    "whole_tumor_voxels": whole_tumor_voxels,
    "whole_tumor_volume_ml": round(whole_tumor_volume_ml, 3),
    "necrotic_voxels": necrotic_voxels,
    "necrotic_volume_ml": round(necrotic_volume_ml, 3),
    "expected_viable_voxels": expected_viable_voxels,
    "expected_viable_volume_ml": round(expected_viable_volume_ml, 3),
    "tolerance_percent": 5.0
}

gt_json_path = os.path.join(gt_dir, f"{sample_id}_boolean_gt.json")
with open(gt_json_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to: {gt_json_path}")
print(f"  WholeTumor volume: {whole_tumor_volume_ml:.2f} mL ({whole_tumor_voxels} voxels)")
print(f"  NecroticCore volume: {necrotic_volume_ml:.2f} mL ({necrotic_voxels} voxels)")
print(f"  Expected viable volume after subtraction: {expected_viable_volume_ml:.2f} mL")
PYEOF

# Create Slicer Python script to set up the scene
SETUP_PYTHON="/tmp/setup_boolean_task.py"
cat > "$SETUP_PYTHON" << 'SLICERPY'
import slicer
import os
import time

# Get sample ID from environment or file
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
if os.path.exists("/tmp/brats_sample_id"):
    with open("/tmp/brats_sample_id") as f:
        sample_id = f.read().strip()

brats_dir = f"/home/ga/Documents/SlicerData/BraTS/{sample_id}"
seg_path = f"/home/ga/Documents/SlicerData/BraTS/{sample_id}_initial_seg.nii.gz"

print(f"Loading BraTS data for: {sample_id}")

# Load FLAIR volume
flair_path = os.path.join(brats_dir, f"{sample_id}_flair.nii.gz")
flair_node = None
if os.path.exists(flair_path):
    flair_node = slicer.util.loadVolume(flair_path)
    flair_node.SetName("FLAIR")
    print(f"Loaded FLAIR volume from {flair_path}")
else:
    print(f"WARNING: FLAIR not found at {flair_path}")
    # Try alternate location
    alt_flair = f"/home/ga/Documents/SlicerData/BraTS/{sample_id}/{sample_id}_flair.nii.gz"
    if os.path.exists(alt_flair):
        flair_node = slicer.util.loadVolume(alt_flair)
        flair_node.SetName("FLAIR")
        print(f"Loaded FLAIR from alternate path")

# Load the initial segmentation labelmap
if os.path.exists(seg_path):
    print(f"Loading segmentation from {seg_path}")
    
    # Load as labelmap
    labelmap_node = slicer.util.loadLabelVolume(seg_path)
    labelmap_node.SetName("TumorLabels")
    
    # Create segmentation node
    seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    seg_node.SetName("TumorSegmentation")
    
    # Import labelmap into segmentation
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(
        labelmap_node, seg_node
    )
    
    # Get the segmentation
    segmentation = seg_node.GetSegmentation()
    
    # Rename segments based on label values
    # After import, segments are typically named "1", "2" or "Segment_1", etc.
    for i in range(segmentation.GetNumberOfSegments()):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        name = segment.GetName()
        
        # Check segment name or ID to determine which is which
        if "1" in segment_id or name == "1":
            segment.SetName("WholeTumor")
            segment.SetColor(1.0, 0.5, 0.0)  # Orange
            print(f"Renamed segment {segment_id} to WholeTumor")
        elif "2" in segment_id or name == "2":
            segment.SetName("NecroticCore")
            segment.SetColor(0.5, 0.0, 0.5)  # Purple
            print(f"Renamed segment {segment_id} to NecroticCore")
    
    # Remove the labelmap node (we only need the segmentation)
    slicer.mrmlScene.RemoveNode(labelmap_node)
    
    # Set up display
    seg_node.CreateDefaultDisplayNodes()
    display_node = seg_node.GetDisplayNode()
    if display_node:
        display_node.SetVisibility(True)
        display_node.SetOpacity2DFill(0.5)
        display_node.SetOpacity2DOutline(1.0)
    
    print(f"Created segmentation with segments: WholeTumor, NecroticCore")
else:
    print(f"ERROR: Initial segmentation not found at {seg_path}")

# Center slice views on tumor region
if flair_node:
    seg_node = slicer.util.getNode("TumorSegmentation")
    if seg_node:
        # Get bounds of segmentation
        bounds = [0]*6
        seg_node.GetBounds(bounds)
        center = [(bounds[0]+bounds[1])/2, (bounds[2]+bounds[3])/2, (bounds[4]+bounds[5])/2]
        
        # Set slice views to center on tumor
        layoutManager = slicer.app.layoutManager()
        for color in ['Red', 'Yellow', 'Green']:
            sliceWidget = layoutManager.sliceWidget(color)
            if sliceWidget:
                sliceLogic = sliceWidget.sliceLogic()
                idx = ['Red', 'Yellow', 'Green'].index(color)
                sliceLogic.SetSliceOffset(center[idx])
        
        print(f"Centered views on tumor at {center}")

# Switch to Segment Editor module
slicer.util.selectModule("SegmentEditor")

# Wait for module to load
time.sleep(1)

# Configure Segment Editor
try:
    editor_widget = slicer.modules.SegmentEditorWidget.editor
    seg_node = slicer.util.getNode("TumorSegmentation")
    if seg_node:
        editor_widget.setSegmentationNode(seg_node)
    if flair_node:
        editor_widget.setSourceVolumeNode(flair_node)
    
    # Select WholeTumor segment
    segmentation = seg_node.GetSegmentation()
    for i in range(segmentation.GetNumberOfSegments()):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        if "WholeTumor" in segment.GetName():
            editor_widget.setCurrentSegmentID(segment_id)
            print(f"Selected WholeTumor segment")
            break
except Exception as e:
    print(f"Warning: Could not fully configure Segment Editor: {e}")

print("\n=== Setup Complete ===")
print("Task: Use Logical operators effect to subtract NecroticCore from WholeTumor")
print("1. Select 'Logical operators' effect")
print("2. Set Operation to 'Subtract'")
print("3. Set Modifier segment to 'NecroticCore'")
print("4. Click Apply")
SLICERPY

chmod 644 "$SETUP_PYTHON"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Record initial state
echo "0" > /tmp/initial_segment_state.txt

# Launch Slicer with setup script
echo "Launching 3D Slicer..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$SETUP_PYTHON" > /tmp/slicer_setup.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
TIMEOUT=90
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1)
        if [ -n "$WINDOW" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait extra time for data to load and module to switch
echo "Waiting for data to load..."
sleep 15

# Maximize window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Store sample ID for verification
echo "$SAMPLE_ID" > /tmp/current_sample_id

echo ""
echo "=== Task Setup Complete ==="
echo "3D Slicer is open with:"
echo "  - FLAIR volume loaded"
echo "  - TumorSegmentation with WholeTumor and NecroticCore segments"
echo "  - Segment Editor module active"
echo ""
echo "TASK: Use Logical operators to subtract NecroticCore from WholeTumor"