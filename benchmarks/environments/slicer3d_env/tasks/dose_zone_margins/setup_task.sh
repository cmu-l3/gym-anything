#!/bin/bash
echo "=== Setting up Dose Zone Margins Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
FLAIR_FILE="$CASE_DIR/${SAMPLE_ID}_flair.nii.gz"
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

echo "Sample ID: $SAMPLE_ID"
echo "FLAIR file: $FLAIR_FILE"

# Verify data exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    exit 1
fi

if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi

# Clean up any previous outputs
rm -f "$BRATS_DIR/dose_zones.seg.nrrd" 2>/dev/null || true
rm -f "$BRATS_DIR/dose_zones.nrrd" 2>/dev/null || true
rm -f /tmp/dose_zone_result.json 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create initial tumor segment from ground truth (enhancing tumor only - label 4)
echo "Creating initial tumor segment from ground truth..."
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

gt_path = "$GT_SEG"
output_path = "$BRATS_DIR/initial_tumor.nii.gz"
stats_path = "/tmp/initial_tumor_stats.json"

print(f"Loading ground truth from: {gt_path}")
gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int32)

# BraTS labels: 0=bg, 1=necrotic core, 2=peritumoral edema, 4=enhancing tumor
# Use label 4 (enhancing tumor) as the primary tumor for margin expansion
tumor_mask = (gt_data == 4)

# If no enhancing tumor, use all tumor labels
if np.sum(tumor_mask) < 100:
    print("Few enhancing tumor voxels, using all tumor labels")
    tumor_mask = (gt_data > 0)

# Create binary tumor segmentation
tumor_seg = tumor_mask.astype(np.int16)

# Save as NIfTI for Slicer to load
tumor_nii = nib.Nifti1Image(tumor_seg, gt_nii.affine, gt_nii.header)
nib.save(tumor_nii, output_path)
print(f"Initial tumor segment saved to: {output_path}")

# Calculate tumor statistics for verification
voxel_dims = gt_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

tumor_voxels = int(np.sum(tumor_mask))
tumor_volume_mm3 = tumor_voxels * voxel_volume_mm3

# Find tumor bounding box for reference
tumor_coords = np.argwhere(tumor_mask)
if len(tumor_coords) > 0:
    tumor_center = tumor_coords.mean(axis=0).tolist()
    tumor_bbox_min = tumor_coords.min(axis=0).tolist()
    tumor_bbox_max = tumor_coords.max(axis=0).tolist()
else:
    tumor_center = [0, 0, 0]
    tumor_bbox_min = [0, 0, 0]
    tumor_bbox_max = [0, 0, 0]

stats = {
    "sample_id": "$SAMPLE_ID",
    "tumor_voxels": tumor_voxels,
    "tumor_volume_mm3": tumor_volume_mm3,
    "tumor_volume_ml": tumor_volume_mm3 / 1000.0,
    "voxel_dims_mm": list(voxel_dims),
    "voxel_volume_mm3": voxel_volume_mm3,
    "tumor_center_voxel": tumor_center,
    "tumor_bbox_min": tumor_bbox_min,
    "tumor_bbox_max": tumor_bbox_max
}

with open(stats_path, "w") as f:
    json.dump(stats, f, indent=2)

print(f"Tumor statistics: {tumor_voxels} voxels, {tumor_volume_mm3/1000:.2f} mL")
PYEOF

# Verify tumor segment was created
if [ ! -f "$BRATS_DIR/initial_tumor.nii.gz" ]; then
    echo "ERROR: Failed to create initial tumor segment"
    exit 1
fi

# Copy ground truth stats to hidden location for verification
cp /tmp/initial_tumor_stats.json "$GROUND_TRUTH_DIR/tumor_stats.json" 2>/dev/null || true
chmod 600 "$GROUND_TRUTH_DIR/tumor_stats.json" 2>/dev/null || true

# Create Slicer Python script to load data and create initial segment
cat > /tmp/load_tumor_data.py << 'PYEOF'
import slicer
import os

# Paths
brats_dir = "/home/ga/Documents/SlicerData/BraTS"
sample_id = open("/tmp/brats_sample_id").read().strip() if os.path.exists("/tmp/brats_sample_id") else "BraTS2021_00000"
case_dir = os.path.join(brats_dir, sample_id)
flair_path = os.path.join(case_dir, f"{sample_id}_flair.nii.gz")
tumor_path = os.path.join(brats_dir, "initial_tumor.nii.gz")

print(f"Loading FLAIR from: {flair_path}")
print(f"Loading tumor from: {tumor_path}")

# Load FLAIR volume
flair_node = slicer.util.loadVolume(flair_path)
if flair_node:
    flair_node.SetName("FLAIR")
    print("FLAIR volume loaded successfully")
else:
    print("ERROR: Failed to load FLAIR volume")

# Load tumor labelmap and convert to segmentation
tumor_labelmap = slicer.util.loadLabelVolume(tumor_path)
if tumor_labelmap:
    tumor_labelmap.SetName("TumorLabelmap")
    
    # Create segmentation node
    seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    seg_node.SetName("DoseZones")
    seg_node.SetReferenceImageGeometryParameterFromVolumeNode(flair_node)
    
    # Import labelmap as segment
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(
        tumor_labelmap, seg_node)
    
    # Rename the segment to "Tumor"
    segmentation = seg_node.GetSegmentation()
    if segmentation.GetNumberOfSegments() > 0:
        segment_id = segmentation.GetNthSegmentID(0)
        segment = segmentation.GetSegment(segment_id)
        segment.SetName("Tumor")
        # Set tumor color to a distinct color (not red/yellow/green)
        segment.SetColor(0.5, 0.0, 0.5)  # Purple
        print("Tumor segment created and named")
    
    # Remove the temporary labelmap node
    slicer.mrmlScene.RemoveNode(tumor_labelmap)
    
    # Show segmentation in 3D
    seg_node.CreateClosedSurfaceRepresentation()
    
    print("Segmentation node created with Tumor segment")
else:
    print("ERROR: Failed to load tumor labelmap")

# Set up slice views to show the data
slicer.util.setSliceViewerLayers(background=flair_node)

# Center on tumor
layoutManager = slicer.app.layoutManager()
for sliceViewName in layoutManager.sliceViewNames():
    sliceWidget = layoutManager.sliceWidget(sliceViewName)
    sliceWidget.sliceController().fitSliceToBackground()

# Switch to Four-Up layout to see 3D view
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Go to Segment Editor module
slicer.util.selectModule("SegmentEditor")

print("Setup complete - ready for dose zone creation")
PYEOF

chmod 644 /tmp/load_tumor_data.py
chown ga:ga /tmp/load_tumor_data.py

# Launch Slicer with the data loading script
echo "Launching 3D Slicer with BraTS data and tumor segment..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_tumor_data.py > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start and load data
echo "Waiting for Slicer to start and load data..."
sleep 15

# Wait for Slicer window
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data loading
sleep 10

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 2
take_screenshot /tmp/dose_zone_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "STARTING STATE:"
echo "  - FLAIR MRI volume loaded"
echo "  - 'Tumor' segment exists (purple color)"
echo "  - Segment Editor module is active"
echo ""
echo "YOUR TASK:"
echo "  Create 3 concentric margin zones around the tumor:"
echo "  1. Zone1_5mm (0-5mm margin) - RED"
echo "  2. Zone2_10mm (5-10mm margin) - YELLOW"  
echo "  3. Zone3_15mm (10-15mm margin) - GREEN"
echo ""
echo "  Use Margin effect to expand, then Logical operators to subtract."
echo "  Save to: ~/Documents/SlicerData/BraTS/dose_zones.seg.nrrd"
echo ""