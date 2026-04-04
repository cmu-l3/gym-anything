#!/bin/bash
echo "=== Setting up Segmentation Margin Expansion Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"

# Verify required files exist
if [ ! -f "$SAMPLE_DIR/${SAMPLE_ID}_t1ce.nii.gz" ]; then
    echo "ERROR: T1ce volume not found!"
    exit 1
fi

if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi

# Record initial state
rm -f /tmp/margin_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/treatment_volumes.seg.nrrd" 2>/dev/null || true
rm -f "$BRATS_DIR/treatment_volumes_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso

# Create GTV segmentation from enhancing tumor (label 4 in BraTS)
echo "Creating initial GTV segmentation from enhancing tumor..."

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

try:
    from scipy import ndimage
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy import ndimage

sample_id = "$SAMPLE_ID"
gt_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
brats_dir = "$BRATS_DIR"
output_gtv = os.path.join(brats_dir, "initial_gtv.nii.gz")
gt_info_path = "$GROUND_TRUTH_DIR/margin_task_ground_truth.json"

print(f"Loading ground truth: {gt_path}")
seg_nii = nib.load(gt_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
header = seg_nii.header

# Get voxel dimensions
voxel_dims = header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))
print(f"Voxel dimensions: {voxel_dims} mm")
print(f"Voxel volume: {voxel_volume_mm3:.4f} mm³")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# For GTV, we use the whole tumor core (labels 1 and 4) or just enhancing (4)
# Using whole tumor (all non-zero) for a more meaningful GTV
gtv_mask = (seg_data > 0).astype(np.int16)

gtv_voxels = np.sum(gtv_mask > 0)
gtv_volume_mm3 = gtv_voxels * voxel_volume_mm3
gtv_volume_ml = gtv_volume_mm3 / 1000.0

print(f"GTV voxels: {gtv_voxels}")
print(f"GTV volume: {gtv_volume_ml:.2f} mL")

# Save GTV as NIfTI
gtv_nii = nib.Nifti1Image(gtv_mask, affine, header)
nib.save(gtv_nii, output_gtv)
print(f"Saved initial GTV to: {output_gtv}")

# Calculate expected CTV and PTV volumes using morphological dilation
# CTV: 5mm margin
# PTV: 8mm margin
ctv_margin_mm = 5.0
ptv_margin_mm = 8.0

# Convert margins to voxels (use average voxel size for isotropic approximation)
avg_voxel_size = np.mean(voxel_dims)
ctv_margin_voxels = ctv_margin_mm / avg_voxel_size
ptv_margin_voxels = ptv_margin_mm / avg_voxel_size

print(f"CTV margin: {ctv_margin_mm}mm = ~{ctv_margin_voxels:.1f} voxels")
print(f"PTV margin: {ptv_margin_mm}mm = ~{ptv_margin_voxels:.1f} voxels")

# Create spherical structuring elements
def create_sphere_struct(radius_voxels, voxel_dims):
    """Create an anisotropic sphere accounting for voxel dimensions."""
    # Size of the structuring element in each dimension
    sizes = [int(np.ceil(2 * radius_voxels * avg_voxel_size / d)) + 1 for d in voxel_dims]
    # Ensure odd sizes
    sizes = [s if s % 2 == 1 else s + 1 for s in sizes]
    
    # Create coordinate grids
    ranges = [np.arange(-(s//2), s//2 + 1) * d for s, d in zip(sizes, voxel_dims)]
    Z, Y, X = np.meshgrid(*ranges, indexing='ij')
    
    # Sphere equation
    dist = np.sqrt(X**2 + Y**2 + Z**2)
    sphere = (dist <= radius_voxels * avg_voxel_size).astype(np.uint8)
    return sphere

# For efficiency, use iterations of binary dilation with a small structuring element
# Calculate iterations needed
ctv_iterations = max(1, int(round(ctv_margin_voxels)))
ptv_iterations = max(1, int(round(ptv_margin_voxels)))

print(f"Using {ctv_iterations} dilation iterations for CTV")
print(f"Using {ptv_iterations} dilation iterations for PTV")

# Dilate for CTV
ctv_mask = ndimage.binary_dilation(gtv_mask > 0, iterations=ctv_iterations).astype(np.int16)
ctv_voxels = np.sum(ctv_mask > 0)
ctv_volume_mm3 = ctv_voxels * voxel_volume_mm3
ctv_volume_ml = ctv_volume_mm3 / 1000.0

# Dilate for PTV
ptv_mask = ndimage.binary_dilation(gtv_mask > 0, iterations=ptv_iterations).astype(np.int16)
ptv_voxels = np.sum(ptv_mask > 0)
ptv_volume_mm3 = ptv_voxels * voxel_volume_mm3
ptv_volume_ml = ptv_volume_mm3 / 1000.0

print(f"Expected CTV volume: {ctv_volume_ml:.2f} mL ({ctv_voxels} voxels)")
print(f"Expected PTV volume: {ptv_volume_ml:.2f} mL ({ptv_voxels} voxels)")

# Save ground truth info for verification
gt_info = {
    "sample_id": sample_id,
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_mm3": voxel_volume_mm3,
    "gtv_voxels": int(gtv_voxels),
    "gtv_volume_ml": float(gtv_volume_ml),
    "ctv_margin_mm": ctv_margin_mm,
    "ptv_margin_mm": ptv_margin_mm,
    "expected_ctv_voxels": int(ctv_voxels),
    "expected_ctv_volume_ml": float(ctv_volume_ml),
    "expected_ptv_voxels": int(ptv_voxels),
    "expected_ptv_volume_ml": float(ptv_volume_ml),
    "ctv_iterations_used": ctv_iterations,
    "ptv_iterations_used": ptv_iterations,
}

with open(gt_info_path, 'w') as f:
    json.dump(gt_info, f, indent=2)
print(f"Saved ground truth info to: {gt_info_path}")

# Also save expected CTV and PTV for nesting verification
ctv_nii = nib.Nifti1Image(ctv_mask, affine, header)
nib.save(ctv_nii, os.path.join("$GROUND_TRUTH_DIR", "expected_ctv.nii.gz"))

ptv_nii = nib.Nifti1Image(ptv_mask, affine, header)
nib.save(ptv_nii, os.path.join("$GROUND_TRUTH_DIR", "expected_ptv.nii.gz"))

print("Ground truth preparation complete!")
PYEOF

# Verify GTV was created
if [ ! -f "$BRATS_DIR/initial_gtv.nii.gz" ]; then
    echo "ERROR: Failed to create initial GTV segmentation"
    exit 1
fi

# Create Slicer Python script to load volumes and create initial segmentation
cat > /tmp/setup_margin_task.py << 'PYEOF'
import slicer
import os
import vtk

sample_dir = os.environ.get("SAMPLE_DIR", "/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000")
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")

print(f"Setting up margin expansion task for {sample_id}...")

# Load the T1ce volume as reference
t1ce_path = os.path.join(sample_dir, f"{sample_id}_t1ce.nii.gz")
print(f"Loading T1ce: {t1ce_path}")
volume_node = slicer.util.loadVolume(t1ce_path)
if volume_node:
    volume_node.SetName("T1_Contrast")
    print("T1ce loaded successfully")
else:
    print("ERROR: Failed to load T1ce")

# Load the initial GTV segmentation
gtv_path = os.path.join(brats_dir, "initial_gtv.nii.gz")
print(f"Loading GTV labelmap: {gtv_path}")

# Create a segmentation node
segmentation_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode", "TreatmentVolumes")

# Import GTV from labelmap
gtv_labelmap = slicer.util.loadLabelVolume(gtv_path)
if gtv_labelmap:
    gtv_labelmap.SetName("GTV_labelmap")
    
    # Import into segmentation
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(gtv_labelmap, segmentation_node)
    
    # Get the segment that was created and rename it
    segmentation = segmentation_node.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segment_id = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName("GTV")
        # Set GTV color to red
        segment.SetColor(1.0, 0.0, 0.0)
        print(f"GTV segment created with ID: {segment_id}")
    
    # Remove the temporary labelmap
    slicer.mrmlScene.RemoveNode(gtv_labelmap)
else:
    print("ERROR: Failed to load GTV labelmap")

# Set up views
if volume_node:
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Link segmentation to volume
    segmentation_node.SetReferenceImageGeometryParameterFromVolumeNode(volume_node)
    
    slicer.util.resetSliceViews()

# Switch to Segment Editor module
slicer.util.selectModule("SegmentEditor")

# Set the segmentation node in Segment Editor
segmentEditorWidget = slicer.modules.SegmentEditorWidget.editor
segmentEditorWidget.setSegmentationNode(segmentation_node)
segmentEditorWidget.setSourceVolumeNode(volume_node)

print("")
print("=" * 60)
print("TASK: Create CTV and PTV by expanding the GTV segment")
print("=" * 60)
print("")
print("Current state:")
print("  - GTV segment is loaded (red)")
print("  - Use Segment Editor's 'Margin' effect to expand")
print("")
print("Steps:")
print("  1. Duplicate GTV or create new segment 'CTV'")
print("  2. Apply 5mm margin (grow) to create CTV")
print("  3. Create another segment 'PTV'") 
print("  4. Apply 8mm margin (grow) from original GTV")
print("")
print("Save to: ~/Documents/SlicerData/BraTS/treatment_volumes.seg.nrrd")
print("=" * 60)
PYEOF

export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"
export BRATS_DIR="$BRATS_DIR"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the setup script
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" BRATS_DIR="$BRATS_DIR" \
    /opt/Slicer/Slicer --python-script /tmp/setup_margin_task.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/margin_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Segmentation Margin Expansion"
echo "===================================="
echo ""
echo "A tumor segmentation 'GTV' (Gross Tumor Volume) is loaded."
echo "Create treatment planning volumes by EXPANDING this segmentation:"
echo ""
echo "1. Create 'CTV' (Clinical Target Volume):"
echo "   - Expand GTV by 5mm margin"
echo ""
echo "2. Create 'PTV' (Planning Target Volume):"
echo "   - Expand original GTV by 8mm margin"
echo ""
echo "Use the Segment Editor 'Margin' effect."
echo "Ensure proper nesting: GTV ⊂ CTV ⊂ PTV"
echo ""
echo "Save outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/BraTS/treatment_volumes.seg.nrrd"
echo "  - Report JSON: ~/Documents/SlicerData/BraTS/treatment_volumes_report.json"
echo ""