#!/bin/bash
echo "=== Setting up Bilateral Kidney Volume Ratio Analysis Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORT_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean previous task artifacts
rm -f "$EXPORT_DIR/kidney_analysis.txt" 2>/dev/null || true
rm -f /tmp/kidney_task_result.json 2>/dev/null || true

# Set proper permissions
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true
chmod -R 755 /home/ga/Documents/SlicerData 2>/dev/null || true

# Prepare AMOS data
echo "Preparing abdominal CT data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR

# Run data preparation script if it exists
if [ -f "/workspace/scripts/prepare_amos_data.sh" ]; then
    /workspace/scripts/prepare_amos_data.sh "$CASE_ID"
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# If data preparation didn't create files, generate synthetic data
if [ ! -f "$CT_FILE" ]; then
    echo "Generating synthetic abdominal CT with kidneys..."
    
    pip3 install -q numpy nibabel 2>/dev/null || true
    
    python3 << 'PYEOF'
import os
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

np.random.seed(42)

# Create realistic abdominal CT dimensions
nx, ny, nz = 256, 256, 100
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Generate CT volume with realistic HU values
ct_data = np.zeros((nx, ny, nz), dtype=np.int16)
ct_data[:] = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Body outline
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2
body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (80**2)) <= 1.0

# Air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine
spine_cx, spine_cy = center_x, center_y + 50
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 15**2
    ct_data[:, :, z][spine_mask] = np.random.normal(500, 80, (np.sum(spine_mask),)).astype(np.int16)

# Create RIGHT kidney (slightly smaller) - positioned on left side of image (patient's right)
right_kidney_cx, right_kidney_cy = center_x - 60, center_y + 20
right_kidney_rx, right_kidney_ry = 25, 20  # Semi-axes

# Create LEFT kidney (slightly larger) - positioned on right side of image (patient's left)
left_kidney_cx, left_kidney_cy = center_x + 60, center_y + 20
left_kidney_rx, left_kidney_ry = 28, 22  # Slightly larger semi-axes

# Create kidney labelmap
label_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Generate kidneys across multiple slices (z = 30 to 70)
for z in range(30, 70):
    z_factor = 1.0 - abs(z - 50) / 25.0  # Taper at ends
    z_factor = max(0.3, z_factor)
    
    # Right kidney (label 1)
    r_rx = right_kidney_rx * z_factor
    r_ry = right_kidney_ry * z_factor
    right_mask = ((X - right_kidney_cx)**2 / r_rx**2 + (Y - right_kidney_cy)**2 / r_ry**2) <= 1.0
    ct_data[:, :, z][right_mask & body_mask] = np.random.normal(40, 10, (np.sum(right_mask & body_mask),)).astype(np.int16)
    label_data[:, :, z][right_mask & body_mask] = 1
    
    # Left kidney (label 2)
    l_rx = left_kidney_rx * z_factor
    l_ry = left_kidney_ry * z_factor
    left_mask = ((X - left_kidney_cx)**2 / l_rx**2 + (Y - left_kidney_cy)**2 / l_ry**2) <= 1.0
    ct_data[:, :, z][left_mask & body_mask] = np.random.normal(40, 10, (np.sum(left_mask & body_mask),)).astype(np.int16)
    label_data[:, :, z][left_mask & body_mask] = 2

# Save CT volume
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
ct_img = nib.Nifti1Image(ct_data, affine)
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path}")

# Save kidney segmentation labelmap
seg_path = os.path.join(amos_dir, "kidney_segmentation.nii.gz")
seg_img = nib.Nifti1Image(label_data, affine)
nib.save(seg_img, seg_path)
print(f"Kidney segmentation saved: {seg_path}")

# Calculate ground truth volumes
voxel_volume_mm3 = float(np.prod(spacing))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

right_voxels = np.sum(label_data == 1)
left_voxels = np.sum(label_data == 2)

right_volume_ml = right_voxels * voxel_volume_ml
left_volume_ml = left_voxels * voxel_volume_ml

larger_kidney = "RIGHT" if right_volume_ml > left_volume_ml else "LEFT"
max_vol = max(right_volume_ml, left_volume_ml)
min_vol = min(right_volume_ml, left_volume_ml)
volume_ratio = max_vol / min_vol if min_vol > 0 else 1.0

gt_values = {
    "right_kidney_volume_ml": round(right_volume_ml, 1),
    "left_kidney_volume_ml": round(left_volume_ml, 1),
    "volume_ratio": round(volume_ratio, 3),
    "larger_kidney": larger_kidney,
    "preserve_recommendation": larger_kidney,
    "voxel_volume_ml": voxel_volume_ml,
    "right_voxels": int(right_voxels),
    "left_voxels": int(left_voxels)
}

gt_path = os.path.join(gt_dir, "kidney_volume_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_values, f, indent=2)

print(f"Ground truth saved: {gt_path}")
print(f"Right kidney: {right_volume_ml:.1f} mL ({right_voxels} voxels)")
print(f"Left kidney: {left_volume_ml:.1f} mL ({left_voxels} voxels)")
print(f"Ratio: {volume_ratio:.3f}")
print(f"Preserve: {larger_kidney}")
PYEOF
fi

# Set permissions on ground truth
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Verify required files exist
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
SEG_FILE="$AMOS_DIR/kidney_segmentation.nii.gz"

if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi

if [ ! -f "$SEG_FILE" ]; then
    echo "ERROR: Segmentation file not found at $SEG_FILE"
    exit 1
fi

echo "CT file: $CT_FILE"
echo "Segmentation file: $SEG_FILE"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer Python script to load data
LOAD_SCRIPT="/tmp/load_kidney_data.py"
cat > "$LOAD_SCRIPT" << 'SLICERPY'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz"
seg_path = "/home/ga/Documents/SlicerData/AMOS/kidney_segmentation.nii.gz"

print("Loading CT volume...")
volumeNode = slicer.util.loadVolume(ct_path)
volumeNode.SetName("AbdominalCT")

print("Loading kidney segmentation...")
labelmapNode = slicer.util.loadLabelVolume(seg_path)
labelmapNode.SetName("KidneyLabels")

# Convert labelmap to segmentation for Segment Statistics
segmentationNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
segmentationNode.SetName("KidneySegmentation")
slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmapNode, segmentationNode)

# Rename segments
segmentation = segmentationNode.GetSegmentation()
for i in range(segmentation.GetNumberOfSegments()):
    segmentID = segmentation.GetNthSegmentID(i)
    segment = segmentation.GetSegment(segmentID)
    name = segment.GetName()
    if "1" in name:
        segment.SetName("Right Kidney")
        segment.SetColor(0.9, 0.4, 0.4)
    elif "2" in name:
        segment.SetName("Left Kidney")
        segment.SetColor(0.4, 0.4, 0.9)

# Remove labelmap node
slicer.mrmlScene.RemoveNode(labelmapNode)

# Set up views
slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Center views
for color in ['Red', 'Yellow', 'Green']:
    sliceWidget = slicer.app.layoutManager().sliceWidget(color)
    sliceWidget.sliceController().fitSliceToBackground()

# Show segmentation in slice views
segmentationNode.CreateClosedSurfaceRepresentation()
displayNode = segmentationNode.GetDisplayNode()
if displayNode:
    displayNode.SetVisibility2DFill(True)
    displayNode.SetVisibility2DOutline(True)
    displayNode.SetOpacity2DFill(0.5)

print("=" * 50)
print("Data loaded successfully!")
print("CT Volume: AbdominalCT")
print("Segmentation: KidneySegmentation")
print("  - Right Kidney (label 1)")
print("  - Left Kidney (label 2)")
print("=" * 50)
print("TASK: Use Segment Statistics to compute kidney volumes")
print("      and create report at ~/Documents/SlicerData/Exports/kidney_analysis.txt")
SLICERPY

chown ga:ga "$LOAD_SCRIPT"

# Launch 3D Slicer
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Give Slicer time to fully initialize
sleep 5

# Execute the load script in Slicer
echo "Loading data into Slicer..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$LOAD_SCRIPT" > /tmp/slicer_load.log 2>&1 &

# Wait for data to load
sleep 15

# Focus and maximize Slicer window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
fi

# Take initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Bilateral Kidney Volume Analysis"
echo "--------------------------------------"
echo "CT Volume and Kidney Segmentation are loaded."
echo ""
echo "Steps:"
echo "1. Go to Segment Statistics module (Quantification > Segment Statistics)"
echo "2. Set Segmentation = KidneySegmentation"
echo "3. Set Scalar Volume = AbdominalCT"
echo "4. Click Apply to compute statistics"
echo "5. Note volumes for each kidney (in mm³, convert to mL by ÷1000)"
echo "6. Create report: ~/Documents/SlicerData/Exports/kidney_analysis.txt"
echo ""
echo "Report format:"
echo "  Right Kidney: <volume> mL"
echo "  Left Kidney: <volume> mL"
echo "  Volume Ratio: <larger/smaller>"
echo "  Preserve: <LEFT or RIGHT> kidney"