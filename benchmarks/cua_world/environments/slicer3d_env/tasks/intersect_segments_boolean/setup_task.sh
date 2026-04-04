#!/bin/bash
echo "=== Setting up Intersect Segments Boolean Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS brain tumor data..."
export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh "BraTS2021_00000"

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using sample: $SAMPLE_ID"

# Verify data exists
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    exit 1
fi

if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi

echo "Data verified: $FLAIR_FILE"

# Create the pre-segmented scene with Tumor and Motor_Region segments
echo "Creating pre-segmented scene with overlapping segments..."

cat > /tmp/create_segments_scene.py << 'PYEOF'
import os
import sys
import json
import numpy as np

# Get environment variables
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

flair_path = os.path.join(brats_dir, sample_id, f"{sample_id}_flair.nii.gz")
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
output_scene = os.path.join(brats_dir, "intersection_task_scene.mrb")
output_gt = os.path.join(gt_dir, "intersection_ground_truth.json")

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

from scipy.ndimage import binary_dilation

print(f"Loading FLAIR: {flair_path}")
flair_nii = nib.load(flair_path)
flair_data = flair_nii.get_fdata()
affine = flair_nii.affine
voxel_dims = flair_nii.header.get_zooms()[:3]

print(f"Loading ground truth segmentation: {gt_seg_path}")
gt_nii = nib.load(gt_seg_path)
gt_data = gt_nii.get_fdata().astype(np.int32)

print(f"Volume shape: {flair_data.shape}")
print(f"GT labels present: {np.unique(gt_data)}")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing tumor
# Create tumor segment: all tumor labels combined
tumor_mask = (gt_data > 0).astype(np.uint8)
tumor_voxels = int(np.sum(tumor_mask))
print(f"Tumor segment: {tumor_voxels} voxels")

# Find tumor centroid and bounding box
tumor_coords = np.argwhere(tumor_mask > 0)
if len(tumor_coords) == 0:
    print("ERROR: No tumor voxels found!")
    sys.exit(1)

tumor_centroid = tumor_coords.mean(axis=0)
tumor_min = tumor_coords.min(axis=0)
tumor_max = tumor_coords.max(axis=0)

print(f"Tumor centroid: {tumor_centroid}")
print(f"Tumor bounding box: {tumor_min} to {tumor_max}")

# Create Motor_Region segment as an ellipsoid that partially overlaps the tumor
# Position it to overlap roughly 30-50% of tumor
motor_mask = np.zeros_like(tumor_mask, dtype=np.uint8)

# Create ellipsoid centered near the tumor but offset
# Motor cortex is typically in the precentral gyrus area
# We'll position our "motor region" to partially overlap the tumor

# Offset the ellipsoid center from tumor centroid
offset_direction = np.array([15, 15, 10])  # Offset in voxels
motor_center = tumor_centroid + offset_direction

# Ensure center is within volume bounds
for i in range(3):
    motor_center[i] = max(30, min(flair_data.shape[i] - 30, motor_center[i]))

# Ellipsoid radii (asymmetric to look like a brain region)
# Make it large enough to have significant overlap with tumor
tumor_extent = tumor_max - tumor_min
radii = np.array([
    max(20, tumor_extent[0] * 0.6),
    max(20, tumor_extent[1] * 0.6),
    max(15, tumor_extent[2] * 0.5)
])

print(f"Motor region center: {motor_center}")
print(f"Motor region radii: {radii}")

# Create the ellipsoid mask
Z, Y, X = np.ogrid[:flair_data.shape[0], :flair_data.shape[1], :flair_data.shape[2]]
ellipsoid = (
    ((Z - motor_center[0]) / radii[0]) ** 2 +
    ((Y - motor_center[1]) / radii[1]) ** 2 +
    ((X - motor_center[2]) / radii[2]) ** 2
) <= 1.0

motor_mask[ellipsoid] = 1
motor_voxels = int(np.sum(motor_mask))
print(f"Motor_Region segment: {motor_voxels} voxels")

# Calculate the ground truth intersection
intersection_mask = (tumor_mask > 0) & (motor_mask > 0)
intersection_voxels = int(np.sum(intersection_mask))

if intersection_voxels < 100:
    print("WARNING: Intersection too small, adjusting motor region...")
    # Move motor region closer to tumor centroid
    motor_center = tumor_centroid + offset_direction * 0.3
    for i in range(3):
        motor_center[i] = max(30, min(flair_data.shape[i] - 30, motor_center[i]))
    
    # Recreate motor mask
    motor_mask = np.zeros_like(tumor_mask, dtype=np.uint8)
    ellipsoid = (
        ((Z - motor_center[0]) / radii[0]) ** 2 +
        ((Y - motor_center[1]) / radii[1]) ** 2 +
        ((X - motor_center[2]) / radii[2]) ** 2
    ) <= 1.0
    motor_mask[ellipsoid] = 1
    motor_voxels = int(np.sum(motor_mask))
    
    # Recalculate intersection
    intersection_mask = (tumor_mask > 0) & (motor_mask > 0)
    intersection_voxels = int(np.sum(intersection_mask))
    print(f"Adjusted Motor_Region: {motor_voxels} voxels")

print(f"Ground truth intersection: {intersection_voxels} voxels")

# Calculate intersection centroid
if intersection_voxels > 0:
    int_coords = np.argwhere(intersection_mask > 0)
    int_centroid = int_coords.mean(axis=0).tolist()
else:
    int_centroid = [0, 0, 0]

# Save combined labelmap for Slicer to load
# 1 = Tumor, 2 = Motor_Region (non-overlapping part), 3 = overlap (for visualization reference)
combined_labelmap = np.zeros_like(tumor_mask, dtype=np.int16)
combined_labelmap[tumor_mask > 0] = 1
combined_labelmap[motor_mask > 0] = 2
# Note: overlap voxels will show as 2, which is fine - the segments are separate

# Save as two separate labelmaps for proper segment import
tumor_labelmap_path = os.path.join(brats_dir, "tumor_segment.nii.gz")
motor_labelmap_path = os.path.join(brats_dir, "motor_segment.nii.gz")

tumor_nii = nib.Nifti1Image(tumor_mask.astype(np.int16), affine)
nib.save(tumor_nii, tumor_labelmap_path)
print(f"Saved tumor labelmap: {tumor_labelmap_path}")

motor_nii = nib.Nifti1Image(motor_mask.astype(np.int16), affine)
nib.save(motor_nii, motor_labelmap_path)
print(f"Saved motor labelmap: {motor_labelmap_path}")

# Save ground truth for verification
gt_info = {
    "sample_id": sample_id,
    "flair_path": flair_path,
    "tumor_segment_name": "Tumor",
    "motor_segment_name": "Motor_Region",
    "expected_intersection_name": "Tumor_Motor_Overlap",
    "tumor_voxels": tumor_voxels,
    "motor_voxels": motor_voxels,
    "expected_intersection_voxels": intersection_voxels,
    "intersection_centroid_ijk": int_centroid,
    "tumor_centroid_ijk": tumor_centroid.tolist(),
    "motor_center_ijk": motor_center.tolist(),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "volume_shape": list(flair_data.shape)
}

with open(output_gt, "w") as f:
    json.dump(gt_info, f, indent=2)

print(f"\nGround truth saved to: {output_gt}")
print(f"Expected intersection voxels: {intersection_voxels}")

# Save paths for Slicer loading
paths_file = "/tmp/segment_paths.json"
with open(paths_file, "w") as f:
    json.dump({
        "flair": flair_path,
        "tumor_labelmap": tumor_labelmap_path,
        "motor_labelmap": motor_labelmap_path
    }, f)

print("\nSetup complete!")
PYEOF

export SAMPLE_ID BRATS_DIR GROUND_TRUTH_DIR
python3 /tmp/create_segments_scene.py

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create segment scene"
    exit 1
fi

# Record initial segment state (no intersection segment yet)
echo '{"intersection_exists": false, "tumor_voxels": 0, "motor_voxels": 0}' > /tmp/initial_segment_state.json

# Clear any previous results
rm -f /tmp/intersection_task_result.json 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer Python script to load data and set up scene
cat > /tmp/load_intersection_scene.py << 'SLICEREOF'
import slicer
import json
import os
import time

# Load paths
with open("/tmp/segment_paths.json") as f:
    paths = json.load(f)

print("Loading FLAIR volume...")
flair_node = slicer.util.loadVolume(paths["flair"])
flair_node.SetName("BrainMRI_FLAIR")

print("Creating segmentation node...")
segmentation_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
segmentation_node.SetName("BrainSegmentation")
segmentation_node.CreateDefaultDisplayNodes()
segmentation_node.SetReferenceImageGeometryParameterFromVolumeNode(flair_node)

# Import tumor segment from labelmap
print("Importing Tumor segment...")
tumor_labelmap = slicer.util.loadLabelVolume(paths["tumor_labelmap"])
tumor_labelmap.SetName("TumorLabelmap")

# Get the segmentation logic
segmentationsLogic = slicer.modules.segmentations.logic()

# Import tumor labelmap as segment
segmentationsLogic.ImportLabelmapToSegmentationNode(tumor_labelmap, segmentation_node)

# Get the imported segment and rename it
segmentation = segmentation_node.GetSegmentation()
tumor_segment_id = segmentation.GetNthSegmentID(0)
tumor_segment = segmentation.GetSegment(tumor_segment_id)
tumor_segment.SetName("Tumor")
tumor_segment.SetColor(0.9, 0.2, 0.2)  # Red

# Remove temporary labelmap node
slicer.mrmlScene.RemoveNode(tumor_labelmap)

print("Importing Motor_Region segment...")
motor_labelmap = slicer.util.loadLabelVolume(paths["motor_labelmap"])
motor_labelmap.SetName("MotorLabelmap")

# Import motor labelmap as segment
segmentationsLogic.ImportLabelmapToSegmentationNode(motor_labelmap, segmentation_node)

# Get the new segment and rename it
motor_segment_id = segmentation.GetNthSegmentID(1)
motor_segment = segmentation.GetSegment(motor_segment_id)
motor_segment.SetName("Motor_Region")
motor_segment.SetColor(0.2, 0.4, 0.9)  # Blue

# Remove temporary labelmap node
slicer.mrmlScene.RemoveNode(motor_labelmap)

print(f"Segments in scene: {segmentation.GetNumberOfSegments()}")
for i in range(segmentation.GetNumberOfSegments()):
    seg_id = segmentation.GetNthSegmentID(i)
    seg = segmentation.GetSegment(seg_id)
    print(f"  {i}: {seg.GetName()}")

# Set up the view
print("Configuring views...")
slicer.util.setSliceViewerLayers(background=flair_node)

# Navigate to tumor location
import numpy as np
tumor_coords = np.array([0, 0, 0])
# Get tumor centroid from ground truth
try:
    with open("/var/lib/slicer/ground_truth/intersection_ground_truth.json") as f:
        gt = json.load(f)
        tumor_centroid = gt.get("tumor_centroid_ijk", [80, 100, 80])
        # Convert IJK to RAS
        volume_ras = [0, 0, 0, 1]
        flair_node.GetRASToIJKMatrix()
        # Just use center of volume for now
        bounds = [0]*6
        flair_node.GetBounds(bounds)
        ras_center = [(bounds[0]+bounds[1])/2, (bounds[2]+bounds[3])/2, (bounds[4]+bounds[5])/2]
except Exception as e:
    print(f"Could not load ground truth: {e}")
    ras_center = [0, 0, 0]

# Center views on volume
slicer.util.resetSliceViews()

# Switch to Segment Editor module
slicer.util.selectModule("SegmentEditor")

# Set up segment editor with our segmentation
editorWidget = slicer.modules.segmenteditor.widgetRepresentation().self()
if editorWidget:
    editorWidget.setSegmentationNode(segmentation_node)
    editorWidget.setSourceVolumeNode(flair_node)

print("\n=== Scene Setup Complete ===")
print("Two segments are loaded: 'Tumor' (red) and 'Motor_Region' (blue)")
print("Use Segment Editor > Logical operators > Intersect to create the overlap segment")
print("Name the new segment: 'Tumor_Motor_Overlap'")
SLICEREOF

# Launch Slicer with the setup script
echo "Launching 3D Slicer with pre-segmented scene..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_intersection_scene.py > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
wait_for_slicer 90

# Focus and maximize
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/intersection_task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create segment intersection"
echo "  - 'Tumor' segment (red) and 'Motor_Region' segment (blue) are loaded"
echo "  - Create a NEW segment named 'Tumor_Motor_Overlap'"
echo "  - Use Segment Editor > Logical operators > Intersect"
echo "  - The result should contain only voxels in BOTH segments"
echo ""