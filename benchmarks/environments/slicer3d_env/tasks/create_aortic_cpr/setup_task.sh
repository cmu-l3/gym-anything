#!/bin/bash
echo "=== Setting up Aortic CPR Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean any previous outputs
rm -f "$EXPORTS_DIR/aorta_cpr.png" 2>/dev/null || true
rm -f "$EXPORTS_DIR/aorta_centerline.json" 2>/dev/null || true
rm -f "$EXPORTS_DIR/curves_summary.json" 2>/dev/null || true
rm -f /tmp/aortic_cpr_result.json 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_curve_count.txt
ls -1 "$EXPORTS_DIR"/*.json 2>/dev/null | wc -l > /tmp/initial_export_count.txt || echo "0" > /tmp/initial_export_count.txt

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID that was used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
echo "Using CT file: $CT_FILE"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi

# Verify ground truth exists (hidden from agent)
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" ]; then
    echo "WARNING: Ground truth labels not found"
fi

# Compute and store aorta centerline from ground truth for verification
echo "Computing reference aorta centerline from ground truth..."
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

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
case_id = os.environ.get("CASE_ID", "amos_0001")

labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

if not os.path.exists(labels_path):
    print(f"WARNING: Labels not found at {labels_path}")
    # Create minimal reference
    ref_data = {
        "case_id": case_id,
        "aorta_centerline_points": [],
        "aorta_length_mm": 0,
        "has_ground_truth": False
    }
    with open(os.path.join(gt_dir, f"{case_id}_aorta_ref.json"), "w") as f:
        json.dump(ref_data, f, indent=2)
    sys.exit(0)

# Load labels
labels_nii = nib.load(labels_path)
labels_data = labels_nii.get_fdata().astype(np.int16)
affine = labels_nii.affine
spacing = np.abs(np.diag(affine)[:3])

print(f"Labels shape: {labels_data.shape}")
print(f"Voxel spacing: {spacing}")

# Find aorta (label 10)
aorta_mask = (labels_data == 10)
aorta_voxels = np.sum(aorta_mask)
print(f"Aorta voxels: {aorta_voxels}")

if aorta_voxels == 0:
    print("WARNING: No aorta label found")
    ref_data = {
        "case_id": case_id,
        "aorta_centerline_points": [],
        "aorta_length_mm": 0,
        "has_ground_truth": False
    }
    with open(os.path.join(gt_dir, f"{case_id}_aorta_ref.json"), "w") as f:
        json.dump(ref_data, f, indent=2)
    sys.exit(0)

# Compute centerline by finding centroid at each z-level
centerline_points = []
for z in range(labels_data.shape[2]):
    slice_mask = aorta_mask[:, :, z]
    if np.any(slice_mask):
        # Find centroid in this slice
        coords = np.argwhere(slice_mask)
        centroid = coords.mean(axis=0)
        # Convert to physical coordinates (RAS)
        voxel_coord = [centroid[0], centroid[1], z]
        ras_coord = nib.affines.apply_affine(affine, voxel_coord)
        centerline_points.append({
            "z_index": int(z),
            "voxel": [float(centroid[0]), float(centroid[1]), float(z)],
            "ras": [float(ras_coord[0]), float(ras_coord[1]), float(ras_coord[2])]
        })

# Calculate total centerline length
total_length = 0.0
if len(centerline_points) > 1:
    for i in range(1, len(centerline_points)):
        p1 = np.array(centerline_points[i-1]["ras"])
        p2 = np.array(centerline_points[i]["ras"])
        total_length += np.linalg.norm(p2 - p1)

print(f"Computed {len(centerline_points)} centerline points")
print(f"Total aorta length: {total_length:.1f} mm")

# Save reference data
ref_data = {
    "case_id": case_id,
    "aorta_centerline_points": centerline_points,
    "aorta_length_mm": float(total_length),
    "num_slices_with_aorta": len(centerline_points),
    "spacing_mm": spacing.tolist(),
    "has_ground_truth": True
}

ref_path = os.path.join(gt_dir, f"{case_id}_aorta_ref.json")
with open(ref_path, "w") as f:
    json.dump(ref_data, f, indent=2)

print(f"Reference data saved to {ref_path}")
PYEOF

# Store case ID for export script
echo "$CASE_ID" > /tmp/amos_case_id

# Launch 3D Slicer with CT data
echo "Launching 3D Slicer with abdominal CT..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT file
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start and load data..."
wait_for_slicer 120

# Additional wait for data to fully load
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/aortic_cpr_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "CT File: $CT_FILE"
echo "Case ID: $CASE_ID"
echo ""
echo "TASK: Create a curved planar reformation of the aorta"
echo ""
echo "Steps:"
echo "1. Find the aorta in the axial view (bright circle anterior to spine)"
echo "2. Create an Open Curve in Markups module"
echo "3. Place 8+ control points along the aorta centerline"
echo "4. Use Curved Planar Reformat module to generate CPR"
echo "5. Export CPR image to: ~/Documents/SlicerData/Exports/aorta_cpr.png"
echo "6. Save curve to: ~/Documents/SlicerData/Exports/aorta_centerline.json"