#!/bin/bash
echo "=== Setting up Interpolate Sparse Segmentation Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SPARSE_SEG_FILE="$BRATS_DIR/sparse_tumor_seg.nii.gz"
OUTPUT_DIR="$BRATS_DIR/interpolated_scene"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$OUTPUT_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ============================================================
# Step 1: Prepare BraTS data (downloads real data if needed)
# ============================================================
echo "Preparing BraTS brain tumor data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
GT_SEG_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

# Verify data exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    exit 1
fi

if [ ! -f "$GT_SEG_FILE" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG_FILE"
    exit 1
fi

echo "Using sample: $SAMPLE_ID"
echo "FLAIR file: $FLAIR_FILE"
echo "Ground truth: $GT_SEG_FILE"

# ============================================================
# Step 2: Create sparse segmentation (every 5th slice only)
# ============================================================
echo "Creating sparse segmentation from ground truth..."

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

# Get paths from environment
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
sparse_out = os.environ.get("SPARSE_SEG_FILE", f"{brats_dir}/sparse_tumor_seg.nii.gz")

gt_path = f"{gt_dir}/{sample_id}_seg.nii.gz"

print(f"Loading ground truth from: {gt_path}")
gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]

print(f"Ground truth shape: {gt_data.shape}")
print(f"Ground truth labels: {np.unique(gt_data)}")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# We'll convert to binary tumor mask for simplicity
tumor_mask = (gt_data > 0).astype(np.int32)
print(f"Total tumor voxels (full): {np.sum(tumor_mask)}")

# Create sparse version - keep only every 5th slice
sparse_mask = np.zeros_like(tumor_mask)
slice_interval = 5  # Keep every 5th slice

# Find the range of slices containing tumor
tumor_slices = []
for z in range(tumor_mask.shape[2]):
    if np.any(tumor_mask[:, :, z] > 0):
        tumor_slices.append(z)

if tumor_slices:
    z_min, z_max = min(tumor_slices), max(tumor_slices)
    print(f"Tumor present in slices {z_min} to {z_max} ({len(tumor_slices)} slices)")
    
    # Keep every Nth slice
    kept_slices = []
    for z in range(z_min, z_max + 1, slice_interval):
        if z in tumor_slices:
            sparse_mask[:, :, z] = tumor_mask[:, :, z]
            kept_slices.append(z)
    
    print(f"Kept {len(kept_slices)} slices for sparse segmentation")
    print(f"Kept slices: {kept_slices[:10]}..." if len(kept_slices) > 10 else f"Kept slices: {kept_slices}")
else:
    print("WARNING: No tumor found in ground truth!")

sparse_voxels = np.sum(sparse_mask > 0)
full_voxels = np.sum(tumor_mask > 0)
print(f"Sparse tumor voxels: {sparse_voxels}")
print(f"Full tumor voxels: {full_voxels}")
print(f"Sparse/Full ratio: {sparse_voxels/full_voxels:.3f}" if full_voxels > 0 else "N/A")

# Save sparse segmentation
sparse_nii = nib.Nifti1Image(sparse_mask.astype(np.int16), gt_nii.affine, gt_nii.header)
nib.save(sparse_nii, sparse_out)
print(f"Sparse segmentation saved to: {sparse_out}")

# Calculate and save initial statistics for verification
voxel_volume_mm3 = float(np.prod(voxel_dims))

# Count slices with segmentation
sparse_slice_count = sum(1 for z in range(sparse_mask.shape[2]) if np.any(sparse_mask[:, :, z] > 0))
full_slice_count = len(tumor_slices)

# Calculate centroid of sparse segmentation
if sparse_voxels > 0:
    coords = np.argwhere(sparse_mask > 0)
    centroid_voxels = coords.mean(axis=0)
    centroid_mm = [float(c * v) for c, v in zip(centroid_voxels, voxel_dims)]
else:
    centroid_mm = [0, 0, 0]

initial_stats = {
    "sample_id": sample_id,
    "sparse_voxel_count": int(sparse_voxels),
    "full_voxel_count": int(full_voxels),
    "sparse_volume_mm3": float(sparse_voxels * voxel_volume_mm3),
    "full_volume_mm3": float(full_voxels * voxel_volume_mm3),
    "sparse_slice_count": sparse_slice_count,
    "full_slice_count": full_slice_count,
    "total_slices": int(gt_data.shape[2]),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "centroid_mm": centroid_mm,
    "expected_volume_increase": float(full_voxels / sparse_voxels) if sparse_voxels > 0 else 0,
    "slice_interval": slice_interval
}

# Save initial stats for verification
stats_path = f"{gt_dir}/{sample_id}_sparse_stats.json"
with open(stats_path, "w") as f:
    json.dump(initial_stats, f, indent=2)

print(f"\nInitial statistics saved to: {stats_path}")
print(f"Expected volume increase after interpolation: {initial_stats['expected_volume_increase']:.2f}x")
PYEOF

export SAMPLE_ID GROUND_TRUTH_DIR BRATS_DIR SPARSE_SEG_FILE

# Verify sparse segmentation was created
if [ ! -f "$SPARSE_SEG_FILE" ]; then
    echo "ERROR: Sparse segmentation file not created"
    exit 1
fi

echo "Sparse segmentation created successfully"

# Record initial segmentation state
INITIAL_SPARSE_SIZE=$(stat -c %s "$SPARSE_SEG_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_SPARSE_SIZE" > /tmp/initial_sparse_size.txt

# ============================================================
# Step 3: Launch 3D Slicer with data loaded
# ============================================================
echo "Launching 3D Slicer with BraTS data..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load data and set up scene
cat > /tmp/setup_interpolation_scene.py << 'SLICERPY'
import slicer
import os
import time

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")

flair_path = f"{brats_dir}/{sample_id}/{sample_id}_flair.nii.gz"
sparse_seg_path = f"{brats_dir}/sparse_tumor_seg.nii.gz"

print(f"Loading FLAIR: {flair_path}")
print(f"Loading sparse segmentation: {sparse_seg_path}")

# Load FLAIR volume
try:
    flair_node = slicer.util.loadVolume(flair_path)
    flair_node.SetName("FLAIR")
    print("FLAIR loaded successfully")
except Exception as e:
    print(f"ERROR loading FLAIR: {e}")

# Load sparse segmentation as labelmap, then convert to segmentation
try:
    sparse_labelmap = slicer.util.loadLabelVolume(sparse_seg_path)
    sparse_labelmap.SetName("Tumor_Sparse_Labelmap")
    
    # Create segmentation node from labelmap
    seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    seg_node.SetName("TumorSegmentation")
    seg_node.SetReferenceImageGeometryParameterFromVolumeNode(flair_node)
    
    # Import labelmap to segmentation
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(sparse_labelmap, seg_node)
    
    # Rename the segment
    segmentation = seg_node.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segment_id = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName("Tumor_Sparse")
        # Set a distinct color (red)
        segment.SetColor(1.0, 0.2, 0.2)
    
    # Remove the temporary labelmap
    slicer.mrmlScene.RemoveNode(sparse_labelmap)
    
    print("Sparse segmentation loaded and converted to segment")
    
except Exception as e:
    print(f"ERROR loading segmentation: {e}")

# Set up view
slicer.util.setSliceViewerLayers(background=flair_node)

# Go to Segment Editor module
slicer.util.selectModule("SegmentEditor")

# Set the segmentation node in segment editor
segmentEditorWidget = slicer.modules.segmenteditor.widgetRepresentation().self().editor
segmentEditorWidget.setSegmentationNode(seg_node)
segmentEditorWidget.setSourceVolumeNode(flair_node)

# Navigate to a slice with segmentation
# Find a slice that has the sparse segmentation
import numpy as np
seg_array = slicer.util.arrayFromSegmentBinaryLabelmap(seg_node, "Tumor_Sparse", flair_node)
if seg_array is not None:
    # Find middle slice with content
    slices_with_seg = [z for z in range(seg_array.shape[0]) if np.any(seg_array[z, :, :] > 0)]
    if slices_with_seg:
        mid_slice = slices_with_seg[len(slices_with_seg) // 2]
        # Convert to RAS coordinates
        ijk_to_ras = np.array(flair_node.GetIJKToRASMatrix().GetData()).reshape(4, 4)
        ras_z = ijk_to_ras[2, 3] + mid_slice * ijk_to_ras[2, 2]
        
        # Set slice offset
        red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
        red_logic.SetSliceOffset(ras_z)
        print(f"Navigated to slice {mid_slice} (RAS z={ras_z:.1f})")

print("\nScene setup complete!")
print("The sparse segmentation 'Tumor_Sparse' is loaded.")
print("Use 'Fill between slices' effect in Segment Editor to interpolate.")
SLICERPY

# Export environment variables for the Python script
export SAMPLE_ID BRATS_DIR

# Launch Slicer and run setup script
echo "Starting Slicer with setup script..."
su - ga -c "DISPLAY=:1 SAMPLE_ID='$SAMPLE_ID' BRATS_DIR='$BRATS_DIR' /opt/Slicer/Slicer --python-script /tmp/setup_interpolation_scene.py > /tmp/slicer_setup.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for Slicer to load..."
wait_for_slicer 120

# Additional wait for data loading
sleep 10

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "FLAIR loaded: $FLAIR_FILE"
echo "Sparse segmentation loaded: $SPARSE_SEG_FILE"
echo ""
echo "TASK: Use 'Fill between slices' effect to interpolate the sparse segmentation"
echo "      The 'Tumor_Sparse' segment only has annotation on every 5th slice."
echo "      After interpolation, it should be continuous across all tumor slices."