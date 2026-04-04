#!/bin/bash
echo "=== Setting up Tumor Principal Axis Analysis Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

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

# Verify all required MRI files exist
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
)

echo "Verifying MRI volumes..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SAMPLE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $SAMPLE_DIR/$f"
        exit 1
    fi
    echo "  Found: $f"
done

# Verify ground truth segmentation exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous task artifacts
echo "Cleaning previous task artifacts..."
rm -f /tmp/principal_axis_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_centroid.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/principal_axis_report.json" 2>/dev/null || true

# Record initial file state for anti-gaming
echo "Recording initial file state..."
cat > /tmp/initial_file_state.json << EOF
{
    "centroid_file_exists": false,
    "report_file_exists": false,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "sample_id": "$SAMPLE_ID"
}
EOF

# Pre-compute ground truth geometric properties
echo "Computing ground truth geometric properties..."
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
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

print(f"Loading ground truth segmentation: {gt_seg_path}")
seg_nii = nib.load(gt_seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel dimensions (mm): {voxel_dims}")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Whole tumor = all non-zero labels
tumor_mask = (seg_data > 0)
tumor_voxels = np.sum(tumor_mask)
print(f"Total tumor voxels: {tumor_voxels}")

if tumor_voxels == 0:
    print("ERROR: No tumor found in segmentation!")
    sys.exit(1)

# Get tumor voxel coordinates
tumor_coords = np.argwhere(tumor_mask)  # (N, 3) in voxel indices

# Compute centroid in voxel space
centroid_voxel = tumor_coords.mean(axis=0)
print(f"Centroid (voxel): {centroid_voxel}")

# Convert centroid to RAS coordinates using affine
centroid_homog = np.append(centroid_voxel, 1)
centroid_ras = affine.dot(centroid_homog)[:3]
print(f"Centroid (RAS mm): {centroid_ras}")

# Convert tumor coordinates to physical space (mm)
tumor_coords_mm = np.zeros_like(tumor_coords, dtype=float)
for i in range(3):
    tumor_coords_mm[:, i] = tumor_coords[:, i] * voxel_dims[i]

# Compute PCA to find principal axes
centered_coords = tumor_coords_mm - tumor_coords_mm.mean(axis=0)
cov_matrix = np.cov(centered_coords.T)
eigenvalues, eigenvectors = np.linalg.eigh(cov_matrix)

# Sort by eigenvalue (descending) - largest is major axis
sort_idx = np.argsort(eigenvalues)[::-1]
eigenvalues = eigenvalues[sort_idx]
eigenvectors = eigenvectors[:, sort_idx]

# Axis lengths approximated as 4 * sqrt(eigenvalue) = ~95% of data spread
# This is a common heuristic for extent along principal components
axis_lengths = 4.0 * np.sqrt(eigenvalues)
major_axis = axis_lengths[0]
intermediate_axis = axis_lengths[1]
minor_axis = axis_lengths[2]

print(f"Principal axis lengths (mm): Major={major_axis:.1f}, Intermediate={intermediate_axis:.1f}, Minor={minor_axis:.1f}")

# Calculate ratios
elongation_ratio = major_axis / intermediate_axis if intermediate_axis > 0 else 1.0
flatness_ratio = intermediate_axis / minor_axis if minor_axis > 0 else 1.0

# Classification
max_ratio = max(elongation_ratio, flatness_ratio)
if max_ratio < 1.5:
    classification = "Spherical"
elif max_ratio <= 2.5:
    classification = "Ellipsoidal"
else:
    classification = "Elongated"

print(f"Elongation ratio: {elongation_ratio:.2f}")
print(f"Flatness ratio: {flatness_ratio:.2f}")
print(f"Shape classification: {classification}")

# Calculate ellipsoid volume
ellipsoid_volume_mm3 = (4.0/3.0) * np.pi * (major_axis/2) * (intermediate_axis/2) * (minor_axis/2)
ellipsoid_volume_ml = ellipsoid_volume_mm3 / 1000.0

# Also calculate actual segmented volume
voxel_volume_mm3 = float(np.prod(voxel_dims))
actual_volume_mm3 = tumor_voxels * voxel_volume_mm3
actual_volume_ml = actual_volume_mm3 / 1000.0

print(f"Ellipsoid volume: {ellipsoid_volume_ml:.2f} mL")
print(f"Actual segmented volume: {actual_volume_ml:.2f} mL")

# Save ground truth
gt_geometry = {
    "sample_id": sample_id,
    "centroid_voxel": centroid_voxel.tolist(),
    "centroid_ras": centroid_ras.tolist(),
    "major_axis_mm": float(major_axis),
    "intermediate_axis_mm": float(intermediate_axis),
    "minor_axis_mm": float(minor_axis),
    "elongation_ratio": float(elongation_ratio),
    "flatness_ratio": float(flatness_ratio),
    "shape_classification": classification,
    "ellipsoid_volume_ml": float(ellipsoid_volume_ml),
    "actual_volume_ml": float(actual_volume_ml),
    "tumor_voxels": int(tumor_voxels),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "eigenvectors": eigenvectors.tolist(),
    "eigenvalues": eigenvalues.tolist()
}

gt_path = os.path.join(gt_dir, f"{sample_id}_geometry_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_geometry, f, indent=2)

print(f"Ground truth geometry saved to: {gt_path}")

# Also save to /tmp for easy verification access
with open("/tmp/ground_truth_geometry.json", "w") as f:
    json.dump(gt_geometry, f, indent=2)
PYEOF

# Create Slicer Python script to load volumes
cat > /tmp/load_brats_principal_axis.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

volumes = [
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
]

print("Loading BraTS MRI volumes for principal axis analysis...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name}...")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
    else:
        print(f"  WARNING: {filepath} not found")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up views - FLAIR as background (shows full tumor extent)
if loaded_nodes:
    flair_node = None
    for node in loaded_nodes:
        if "FLAIR" in node.GetName():
            flair_node = node
            break
    if not flair_node:
        flair_node = loaded_nodes[0]

    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

    slicer.util.resetSliceViews()

    # Center views on the data
    bounds = [0]*6
    flair_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

print("Setup complete - ready for principal axis analysis")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the loading script
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_principal_axis.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/principal_axis_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Tumor Principal Axis Analysis"
echo "====================================="
echo ""
echo "Your goal: Characterize the tumor's 3D geometry"
echo ""
echo "1. Place a fiducial at the tumor centroid"
echo "   Save to: ~/Documents/SlicerData/BraTS/tumor_centroid.mrk.json"
echo ""
echo "2. Measure the three principal axes (major, intermediate, minor)"
echo ""
echo "3. Calculate ellipsoid volume and shape ratios"
echo ""
echo "4. Create report: ~/Documents/SlicerData/BraTS/principal_axis_report.json"
echo ""