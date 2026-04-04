#!/bin/bash
echo "=== Setting up Merge Tumor Segments Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data
echo "Preparing BraTS 2021 data..."
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

# Verify BraTS data exists
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || echo "Sample directory not found"
    exit 1
fi

if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi

echo "BraTS data verified:"
echo "  T1ce: $T1CE_FILE"
echo "  Ground truth: $GT_SEG"

# Record initial state
date +%s > /tmp/task_start_time.txt
rm -f /tmp/merge_segments_result.json 2>/dev/null || true

# Calculate initial segment statistics for verification
echo "Computing initial segment volumes for verification..."
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

gt_path = "$GT_SEG"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

print(f"Loading ground truth segmentation: {gt_path}")
seg = nib.load(gt_path)
data = seg.get_fdata().astype(np.int32)
voxel_dims = seg.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
necrotic_voxels = int(np.sum(data == 1))
edema_voxels = int(np.sum(data == 2))
enhancing_voxels = int(np.sum(data == 4))
total_tumor_voxels = int(np.sum(data > 0))

initial_stats = {
    "sample_id": sample_id,
    "voxel_volume_mm3": voxel_volume_mm3,
    "necrotic_voxels": necrotic_voxels,
    "edema_voxels": edema_voxels,
    "enhancing_voxels": enhancing_voxels,
    "total_tumor_voxels": total_tumor_voxels,
    "necrotic_volume_ml": necrotic_voxels * voxel_volume_mm3 / 1000.0,
    "edema_volume_ml": edema_voxels * voxel_volume_mm3 / 1000.0,
    "enhancing_volume_ml": enhancing_voxels * voxel_volume_mm3 / 1000.0,
    "total_tumor_volume_ml": total_tumor_voxels * voxel_volume_mm3 / 1000.0,
    "expected_merged_voxels": total_tumor_voxels,
    "expected_merged_volume_ml": total_tumor_voxels * voxel_volume_mm3 / 1000.0
}

# Save initial stats
stats_path = os.path.join(gt_dir, f"{sample_id}_initial_stats.json")
with open(stats_path, "w") as f:
    json.dump(initial_stats, f, indent=2)

print(f"Initial segment statistics:")
print(f"  Necrotic Core: {necrotic_voxels} voxels ({initial_stats['necrotic_volume_ml']:.2f} mL)")
print(f"  Edema: {edema_voxels} voxels ({initial_stats['edema_volume_ml']:.2f} mL)")
print(f"  Enhancing: {enhancing_voxels} voxels ({initial_stats['enhancing_volume_ml']:.2f} mL)")
print(f"  Total Tumor (expected): {total_tumor_voxels} voxels ({initial_stats['total_tumor_volume_ml']:.2f} mL)")
print(f"Saved to: {stats_path}")
PYEOF

# Create Python script to load data and create separate segments
echo "Creating Slicer startup script..."
cat > /tmp/load_brats_segments.py << 'PYEOF'
import slicer
import os
import numpy as np

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

# Load T1ce image as main volume
t1ce_path = os.path.join(brats_dir, sample_id, f"{sample_id}_t1ce.nii.gz")
print(f"Loading T1ce volume: {t1ce_path}")
volume_node = slicer.util.loadVolume(t1ce_path)
volume_node.SetName("BraTS_T1ce")

# Load ground truth segmentation as labelmap
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
print(f"Loading segmentation: {gt_seg_path}")

# Create a segmentation node
segmentation_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
segmentation_node.SetName("BraTS_Segmentation")
segmentation_node.SetReferenceImageGeometryParameterFromVolumeNode(volume_node)

# Load labelmap temporarily
labelmap_node = slicer.util.loadLabelVolume(gt_seg_path)
labelmap_array = slicer.util.arrayFromVolume(labelmap_node)

# Get voxel data
import vtk
from vtkmodules.util import numpy_support

# Create segments for each tumor compartment
# BraTS labels: 1=necrotic, 2=edema, 4=enhancing
segment_configs = [
    (1, "Necrotic_Core", (0.8, 0.2, 0.2)),      # Red
    (2, "Edema", (0.9, 0.9, 0.2)),               # Yellow  
    (4, "Enhancing_Tumor", (0.2, 0.8, 0.2))      # Green
]

for label_value, segment_name, color in segment_configs:
    # Create binary array for this label
    binary_mask = (labelmap_array == label_value).astype(np.uint8)
    
    if np.sum(binary_mask) > 0:
        print(f"Creating segment '{segment_name}': {np.sum(binary_mask)} voxels")
        
        # Add segment to segmentation
        segment_id = segmentation_node.GetSegmentation().AddEmptySegment(segment_name)
        segment = segmentation_node.GetSegmentation().GetSegment(segment_id)
        segment.SetColor(color)
        
        # Create vtkOrientedImageData from numpy array
        import slicer.util
        
        # Create a temporary labelmap for this segment
        temp_labelmap = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        temp_labelmap.SetName(f"temp_{segment_name}")
        
        # Copy geometry from original labelmap
        temp_labelmap.CopyOrientation(labelmap_node)
        
        # Set the binary data
        slicer.util.updateVolumeFromArray(temp_labelmap, binary_mask)
        temp_labelmap.CopyOrientation(labelmap_node)
        
        # Import to segmentation
        slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(
            temp_labelmap, segmentation_node, segment_id
        )
        
        # Remove temporary labelmap
        slicer.mrmlScene.RemoveNode(temp_labelmap)
    else:
        print(f"Warning: No voxels found for label {label_value} ({segment_name})")

# Remove the temporary labelmap node
slicer.mrmlScene.RemoveNode(labelmap_node)

# Set up views
slicer.util.setSliceViewerLayers(background=volume_node)

# Center the 3D view
layoutManager = slicer.app.layoutManager()
threeDWidget = layoutManager.threeDWidget(0)
threeDView = threeDWidget.threeDView()
threeDView.resetFocalPoint()

# Show segmentation in 2D views
segmentation_node.CreateDefaultDisplayNodes()
display_node = segmentation_node.GetDisplayNode()
display_node.SetVisibility(True)
display_node.SetAllSegmentsVisibility(True)

# Navigate to a slice with tumor
# Go to the center of the tumor region
import numpy as np
labelmap_array_check = slicer.util.arrayFromVolume(volume_node)
# Just go to center of volume
center_slice = labelmap_array_check.shape[0] // 2
slicer.app.layoutManager().sliceWidget("Red").sliceController().setSliceOffsetValue(center_slice)

print(f"Segmentation loaded with {segmentation_node.GetSegmentation().GetNumberOfSegments()} segments")
print("Segments:")
for i in range(segmentation_node.GetSegmentation().GetNumberOfSegments()):
    seg_id = segmentation_node.GetSegmentation().GetNthSegmentID(i)
    seg = segmentation_node.GetSegmentation().GetSegment(seg_id)
    print(f"  - {seg.GetName()}")

print("\nTask: Merge all three segments into a new segment named 'Total Tumor'")
print("Use Segment Editor → Logical operators → Add")
PYEOF

# Set environment variables for the script
export SAMPLE_ID BRATS_DIR GROUND_TRUTH_DIR

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer and run the loading script
echo "Launching 3D Slicer with BraTS data..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_segments.py > /tmp/slicer_startup.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start and load data..."
sleep 15

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Give extra time for data to load
sleep 10

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/merge_segments_initial.png ga

# Save sample ID for export script
echo "$SAMPLE_ID" > /tmp/merge_segments_sample_id

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "Segmentation loaded with three tumor segments:"
echo "  - Necrotic_Core (red)"
echo "  - Edema (yellow)"
echo "  - Enhancing_Tumor (green)"
echo ""
echo "TASK: Merge all three segments into 'Total Tumor' using Segment Editor"