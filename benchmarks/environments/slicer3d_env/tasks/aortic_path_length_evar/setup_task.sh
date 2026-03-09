#!/bin/bash
echo "=== Setting up Aortic Path Length EVAR Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 abdominal CT data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Compute ground truth centerline measurements
echo "Computing ground truth aortic centerline..."
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

try:
    from scipy.interpolate import splprep, splev
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.interpolate import splprep, splev

gt_dir = "/var/lib/slicer/ground_truth"
case_id = os.environ.get("CASE_ID", "amos_0001")

# Load segmentation
seg_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if not os.path.exists(seg_path):
    print(f"WARNING: Segmentation not found at {seg_path}")
    # Create default ground truth for synthetic data
    gt_data = {
        "case_id": case_id,
        "path_length_mm": 180.0,
        "straight_length_mm": 165.0,
        "tortuosity_ratio": 1.091,
        "superior_z_mm": 200.0,
        "inferior_z_mm": 50.0,
        "z_span_mm": 150.0,
        "centerline_start_mm": [128.0, 150.0, 200.0],
        "centerline_end_mm": [128.0, 150.0, 50.0],
        "num_centerline_points": 50,
        "spacing_mm": [0.78, 0.78, 2.5]
    }
    gt_path = os.path.join(gt_dir, f"{case_id}_centerline_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(gt_data, f, indent=2)
    print(f"Default ground truth saved to {gt_path}")
    sys.exit(0)

print(f"Loading segmentation: {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int16)
spacing = seg_nii.header.get_zooms()[:3]
affine = seg_nii.affine

# Extract aorta (label 10)
aorta = (seg_data == 10)
if not np.any(aorta):
    print("WARNING: No aorta segmentation found (label 10)")
    # Try to find any vascular structure
    unique_labels = np.unique(seg_data)
    print(f"Available labels: {unique_labels}")
    sys.exit(1)

print(f"Aorta voxels: {np.sum(aorta)}")

# Get aorta voxel coordinates
coords = np.argwhere(aorta)

# Sort by z-coordinate (inferior to superior)
z_sorted_indices = np.argsort(coords[:, 2])
coords_sorted = coords[z_sorted_indices]

# Extract centerline by taking centroid at each z-level
z_levels = np.unique(coords_sorted[:, 2])
centerline_voxels = []

for z in z_levels:
    z_mask = coords_sorted[:, 2] == z
    z_coords = coords_sorted[z_mask]
    if len(z_coords) > 0:
        centroid = z_coords.mean(axis=0)
        centerline_voxels.append(centroid)

centerline_voxels = np.array(centerline_voxels)
print(f"Centerline points: {len(centerline_voxels)}")

# Convert to physical coordinates (mm)
centerline_mm = []
for vox in centerline_voxels:
    phys = nib.affines.apply_affine(affine, vox)
    centerline_mm.append(phys)
centerline_mm = np.array(centerline_mm)

# Compute path length
if len(centerline_mm) >= 4:
    try:
        # Fit spline for smooth centerline
        tck, u = splprep([centerline_mm[:, 0], centerline_mm[:, 1], centerline_mm[:, 2]], s=100, k=3)
        u_fine = np.linspace(0, 1, 500)
        spline_pts = np.array(splev(u_fine, tck)).T
        
        # Compute arc length
        diffs = np.diff(spline_pts, axis=0)
        segment_lengths = np.linalg.norm(diffs, axis=1)
        path_length = np.sum(segment_lengths)
    except Exception as e:
        print(f"Spline fitting failed: {e}, using polyline length")
        diffs = np.diff(centerline_mm, axis=0)
        segment_lengths = np.linalg.norm(diffs, axis=1)
        path_length = np.sum(segment_lengths)
else:
    diffs = np.diff(centerline_mm, axis=0)
    segment_lengths = np.linalg.norm(diffs, axis=1)
    path_length = np.sum(segment_lengths)

# Compute straight-line distance between endpoints
start_pt = centerline_mm[0]
end_pt = centerline_mm[-1]
straight_length = np.linalg.norm(end_pt - start_pt)

# Tortuosity ratio
tortuosity = path_length / straight_length if straight_length > 0 else 1.0

# Z positions
z_min_mm = min(start_pt[2], end_pt[2])
z_max_mm = max(start_pt[2], end_pt[2])

gt_data = {
    "case_id": case_id,
    "path_length_mm": float(round(path_length, 2)),
    "straight_length_mm": float(round(straight_length, 2)),
    "tortuosity_ratio": float(round(tortuosity, 4)),
    "superior_z_mm": float(round(z_max_mm, 2)),
    "inferior_z_mm": float(round(z_min_mm, 2)),
    "z_span_mm": float(round(abs(z_max_mm - z_min_mm), 2)),
    "centerline_start_mm": [float(round(x, 2)) for x in start_pt],
    "centerline_end_mm": [float(round(x, 2)) for x in end_pt],
    "num_centerline_points": len(centerline_mm),
    "spacing_mm": [float(s) for s in spacing]
}

gt_path = os.path.join(gt_dir, f"{case_id}_centerline_gt.json")
os.makedirs(gt_dir, exist_ok=True)
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Path length: {gt_data['path_length_mm']:.1f} mm")
print(f"  Straight length: {gt_data['straight_length_mm']:.1f} mm")
print(f"  Tortuosity ratio: {gt_data['tortuosity_ratio']:.4f}")
print(f"  Z span: {gt_data['z_span_mm']:.1f} mm")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_centerline_gt.json" ]; then
    echo "WARNING: Ground truth file was not created, using defaults"
fi

# Clear any previous agent outputs
echo "Clearing previous outputs..."
rm -f "$AMOS_DIR/aortic_curve.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/aortic_straight.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/evar_measurements.json" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "case_id": "$CASE_ID",
    "ct_file": "$CT_FILE",
    "outputs_cleared": true
}
EOF

# Create a Slicer Python script to load the CT with abdominal window
cat > /tmp/load_amos_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading AMOS CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")

    # Set default abdominal window/level for soft tissue
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Center on data
    bounds = [0]*6
    volume_node.GetBounds(bounds)
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

    print(f"CT loaded with abdominal window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for aortic path length measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal agent interaction
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"

    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1

    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Aortic Path Length Measurement for EVAR Planning"
echo "======================================================="
echo ""
echo "A vascular surgeon needs the actual centerline path length"
echo "of the abdominal aorta to size an endovascular stent-graft."
echo ""
echo "Your goal:"
echo "  1. Navigate to identify the aortic hiatus (~T12 level)"
echo "  2. Navigate to identify the aortic bifurcation (~L4/L5 level)"
echo "  3. Use Markups > Open Curve to trace the aorta centerline"
echo "  4. Place 10-15 control points along the CENTER of the aorta"
echo "  5. Note the curve length from the Markups panel"
echo "  6. Create a straight-line ruler between endpoints"
echo "  7. Calculate tortuosity ratio = path_length / straight_length"
echo ""
echo "Save your outputs to:"
echo "  - Curve: ~/Documents/SlicerData/AMOS/aortic_curve.mrk.json"
echo "  - Ruler: ~/Documents/SlicerData/AMOS/aortic_straight.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/evar_measurements.json"
echo ""