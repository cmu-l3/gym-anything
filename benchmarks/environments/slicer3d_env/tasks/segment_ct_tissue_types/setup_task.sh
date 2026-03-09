#!/bin/bash
echo "=== Setting up Multi-Tissue CT Segmentation Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean any previous task outputs
rm -f "$EXPORTS_DIR/tissue_segmentation.seg.nrrd" 2>/dev/null || true
rm -f "$EXPORTS_DIR/tissue_segmentation.nrrd" 2>/dev/null || true
rm -f /tmp/tissue_seg_result.json 2>/dev/null || true

# Record initial state
ls -la "$EXPORTS_DIR"/*.nrrd 2>/dev/null > /tmp/initial_exports_list.txt || echo "No exports" > /tmp/initial_exports_list.txt
INITIAL_EXPORT_COUNT=$(ls -1 "$EXPORTS_DIR"/*.nrrd 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_EXPORT_COUNT" > /tmp/initial_export_count.txt

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Verify data was prepared
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT data not found at $CT_FILE"
    exit 1
fi

echo "CT data prepared: $CT_FILE"
echo "File size: $(du -h "$CT_FILE" | cut -f1)"

# Compute ground truth segment statistics for verification
echo "Computing expected segment statistics..."
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

amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
case_id = os.environ.get("CASE_ID", "amos_0001")

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
print(f"Loading CT from: {ct_path}")

nii = nib.load(ct_path)
data = nii.get_fdata()
voxel_dims = nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

print(f"Volume shape: {data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")
print(f"HU range: {data.min():.0f} to {data.max():.0f}")

# Calculate expected voxel counts for each tissue type
# Bone: HU > 300
bone_mask = data > 300
bone_voxels = int(np.sum(bone_mask))
bone_volume_ml = bone_voxels * voxel_volume_mm3 / 1000.0

# Soft tissue: HU 0 to 100
soft_mask = (data >= 0) & (data <= 100)
soft_voxels = int(np.sum(soft_mask))
soft_volume_ml = soft_voxels * voxel_volume_mm3 / 1000.0

# Air: HU < -500
air_mask = data < -500
air_voxels = int(np.sum(air_mask))
air_volume_ml = air_voxels * voxel_volume_mm3 / 1000.0

# Total volume
total_voxels = int(data.size)

gt_stats = {
    "case_id": case_id,
    "volume_shape": list(data.shape),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_mm3": voxel_volume_mm3,
    "hu_range": [float(data.min()), float(data.max())],
    "total_voxels": total_voxels,
    "bone": {
        "threshold_min": 300,
        "threshold_max": "max",
        "expected_voxels": bone_voxels,
        "expected_volume_ml": round(bone_volume_ml, 2),
        "tolerance_percent": 20
    },
    "soft_tissue": {
        "threshold_min": 0,
        "threshold_max": 100,
        "expected_voxels": soft_voxels,
        "expected_volume_ml": round(soft_volume_ml, 2),
        "tolerance_percent": 20
    },
    "air": {
        "threshold_min": "min",
        "threshold_max": -500,
        "expected_voxels": air_voxels,
        "expected_volume_ml": round(air_volume_ml, 2),
        "tolerance_percent": 25
    }
}

gt_path = os.path.join(gt_dir, f"{case_id}_tissue_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_stats, f, indent=2)

print(f"\nExpected segment statistics:")
print(f"  Bone: {bone_voxels:,} voxels ({bone_volume_ml:.1f} mL)")
print(f"  Soft Tissue: {soft_voxels:,} voxels ({soft_volume_ml:.1f} mL)")
print(f"  Air: {air_voxels:,} voxels ({air_volume_ml:.1f} mL)")
print(f"\nGround truth saved to: {gt_path}")
PYEOF

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$EXPORTS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the CT volume
echo "Launching 3D Slicer with abdominal CT..."
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        SLICER_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1)
        if [ -n "$SLICER_WINDOW" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Maximize and focus Slicer window
echo "Maximizing Slicer window..."
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Wait for data to load
echo "Waiting for CT data to load..."
sleep 10

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "CT Data: $CT_FILE"
echo "Output Path: $EXPORTS_DIR/tissue_segmentation.seg.nrrd"
echo ""
echo "TASK: Create a multi-tissue segmentation with three segments:"
echo "  1. 'Bone' - threshold HU > 300"
echo "  2. 'Soft Tissue' - threshold HU 0 to 100"
echo "  3. 'Air' - threshold HU < -500"
echo ""
echo "Save the segmentation to: ~/Documents/SlicerData/Exports/tissue_segmentation.seg.nrrd"