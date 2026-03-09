#!/bin/bash
echo "=== Setting up Oblique Slice Reformat Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# Prepare BraTS data
# ============================================================
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using BraTS sample: $SAMPLE_ID"

# Verify data exists
T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"
if [ ! -f "$T1CE_FILE" ]; then
    # Try alternate location
    T1CE_FILE=$(find "$BRATS_DIR" -name "*t1ce*.nii.gz" -type f 2>/dev/null | head -1)
fi

if [ -z "$T1CE_FILE" ] || [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1-CE MRI file not found"
    exit 1
fi

echo "T1-CE file: $T1CE_FILE"

# ============================================================
# Compute tumor centroid for verification
# ============================================================
echo "Computing tumor location for verification..."

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

gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

# Load ground truth segmentation
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
if not os.path.exists(seg_path):
    # Try to find any segmentation file
    import glob
    seg_files = glob.glob(os.path.join(gt_dir, "*_seg.nii.gz"))
    if seg_files:
        seg_path = seg_files[0]
    else:
        print("ERROR: Ground truth segmentation not found")
        sys.exit(1)

print(f"Loading segmentation: {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
voxel_dims = seg_nii.header.get_zooms()[:3]

# Find tumor voxels (any label > 0)
tumor_mask = seg_data > 0
tumor_voxels = np.sum(tumor_mask)

if tumor_voxels == 0:
    print("ERROR: No tumor found in segmentation")
    sys.exit(1)

print(f"Tumor voxels: {tumor_voxels}")

# Compute tumor centroid in voxel coordinates
tumor_coords = np.argwhere(tumor_mask)
centroid_voxel = tumor_coords.mean(axis=0)

# Convert to RAS coordinates (world coordinates)
centroid_ras = nib.affines.apply_affine(affine, centroid_voxel)

# Compute tumor bounding box
min_coords = tumor_coords.min(axis=0)
max_coords = tumor_coords.max(axis=0)
bbox_size_voxels = max_coords - min_coords
bbox_size_mm = bbox_size_voxels * np.array(voxel_dims)

# Save tumor info for verification
tumor_info = {
    "sample_id": sample_id,
    "tumor_voxels": int(tumor_voxels),
    "centroid_voxel": centroid_voxel.tolist(),
    "centroid_ras": centroid_ras.tolist(),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "bbox_min_voxel": min_coords.tolist(),
    "bbox_max_voxel": max_coords.tolist(),
    "bbox_size_mm": bbox_size_mm.tolist(),
    "affine": affine.tolist()
}

tumor_info_path = os.path.join(gt_dir, "tumor_info.json")
with open(tumor_info_path, "w") as f:
    json.dump(tumor_info, f, indent=2)

print(f"Tumor centroid (RAS): {centroid_ras}")
print(f"Tumor bbox size (mm): {bbox_size_mm}")
print(f"Tumor info saved to {tumor_info_path}")
PYEOF

# ============================================================
# Kill any existing Slicer and launch fresh
# ============================================================
echo "Launching 3D Slicer with BraTS data..."

pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with T1-CE file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$T1CE_FILE' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for Slicer to start..."
sleep 10

# Wait for Slicer window
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# ============================================================
# Record initial slice orientation
# ============================================================
echo "Recording initial slice orientation..."

cat > /tmp/record_initial_orientation.py << 'PYEOF'
import slicer
import json
import os

try:
    # Get the Red slice node
    red_slice = slicer.mrmlScene.GetNodeByID("vtkMRMLSliceNodeRed")
    if not red_slice:
        red_slice = slicer.app.layoutManager().sliceWidget("Red").mrmlSliceNode()
    
    if red_slice:
        # Get slice to RAS matrix
        import vtk
        slice_to_ras = vtk.vtkMatrix4x4()
        red_slice.GetSliceToRAS(slice_to_ras)
        
        # Extract matrix elements
        matrix = []
        for i in range(4):
            row = []
            for j in range(4):
                row.append(slice_to_ras.GetElement(i, j))
            matrix.append(row)
        
        # Get orientation name
        orientation = red_slice.GetOrientation()
        
        # Extract slice normal (third column of rotation part)
        normal = [matrix[0][2], matrix[1][2], matrix[2][2]]
        
        # Extract slice position
        position = [matrix[0][3], matrix[1][3], matrix[2][3]]
        
        initial_state = {
            "orientation_name": orientation,
            "slice_to_ras_matrix": matrix,
            "slice_normal": normal,
            "slice_position": position,
            "recorded": True
        }
        
        print(f"Initial orientation: {orientation}")
        print(f"Initial normal: {normal}")
        
        with open("/tmp/initial_slice_orientation.json", "w") as f:
            json.dump(initial_state, f, indent=2)
        
        print("Initial orientation saved")
    else:
        print("ERROR: Could not find Red slice node")
        with open("/tmp/initial_slice_orientation.json", "w") as f:
            json.dump({"recorded": False, "error": "No slice node"}, f)

except Exception as e:
    print(f"ERROR: {e}")
    with open("/tmp/initial_slice_orientation.json", "w") as f:
        json.dump({"recorded": False, "error": str(e)}, f)
PYEOF

# Run the Python script in Slicer
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/record_initial_orientation.py > /tmp/slicer_init_orient.log 2>&1 &
sleep 15

# Check if initial orientation was recorded
if [ -f /tmp/initial_slice_orientation.json ]; then
    echo "Initial slice orientation recorded:"
    cat /tmp/initial_slice_orientation.json
else
    echo "Warning: Could not record initial orientation"
    echo '{"recorded": false, "error": "Script did not complete"}' > /tmp/initial_slice_orientation.json
fi

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured: $(stat -c %s /tmp/task_initial.png 2>/dev/null || echo 0) bytes"
fi

# Clean up previous result
rm -f /tmp/oblique_task_result.json 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create an oblique slice reformat through the brain tumor"
echo ""
echo "The T1-CE MRI with a glioma is loaded in 3D Slicer."
echo "Use the Reformat module to rotate the Red slice to an oblique orientation"
echo "that passes through the tumor."
echo ""
echo "The slice must be rotated at least 15 degrees from any standard orientation"
echo "(Axial, Sagittal, or Coronal)."