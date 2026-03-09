#!/bin/bash
echo "=== Setting up Stereotactic Biopsy Planning Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS brain MRI data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"

echo "Using BraTS case: $SAMPLE_ID"

# Verify all required MRI sequences exist
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

# Generate trajectory planning ground truth
echo "Generating trajectory planning ground truth..."
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
    from scipy.ndimage import distance_transform_edt, center_of_mass
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import distance_transform_edt, center_of_mass

sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

print(f"Loading ground truth segmentation: {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel dimensions: {voxel_dims}")
print(f"Labels present: {np.unique(seg_data)}")

# BraTS labels: 0=background, 1=necrotic, 2=edema, 4=enhancing tumor

# Find enhancing tumor region (label 4) - this is the biopsy target zone
enhancing = (seg_data == 4)
enhancing_voxels = np.sum(enhancing)
print(f"Enhancing tumor voxels: {enhancing_voxels}")

if enhancing_voxels < 100:
    # Fall back to whole tumor if enhancing region is too small
    print("WARNING: Small enhancing region, using whole tumor core")
    target_mask = (seg_data == 4) | (seg_data == 1)
else:
    target_mask = enhancing

# Compute centroid of target region in voxel coordinates
if np.any(target_mask):
    target_voxel = np.array(center_of_mass(target_mask))
else:
    # Fallback to volume center
    target_voxel = np.array(seg_data.shape) / 2

print(f"Target centroid (voxel): {target_voxel}")

# Convert to RAS coordinates
target_ras = nib.affines.apply_affine(affine, target_voxel)
print(f"Target centroid (RAS): {target_ras}")

# Find edema region (label 2) - this represents areas to avoid
edema = (seg_data == 2)
edema_voxels = np.sum(edema)
print(f"Edema voxels: {edema_voxels}")

# Compute distance transform from edema (for clearance checking)
if edema_voxels > 0:
    edema_distance = distance_transform_edt(~edema, sampling=voxel_dims)
else:
    edema_distance = np.ones_like(seg_data, dtype=np.float32) * 100.0

# Define brain bounds for entry point validation
brain_mask = (seg_data > 0)
if np.any(brain_mask):
    brain_bounds = {
        'min': np.min(np.argwhere(brain_mask), axis=0).tolist(),
        'max': np.max(np.argwhere(brain_mask), axis=0).tolist()
    }
else:
    brain_bounds = {'min': [0, 0, 0], 'max': list(seg_data.shape)}

# Compute ideal entry point (directly superior to target, on brain surface)
entry_voxel = target_voxel.copy()
# Move to superior surface (highest Z where brain exists)
z_slice_has_brain = [np.any(brain_mask[:, :, z]) for z in range(seg_data.shape[2])]
max_brain_z = max(i for i, has in enumerate(z_slice_has_brain) if has) if any(z_slice_has_brain) else seg_data.shape[2] - 10
entry_voxel[2] = max_brain_z - 5  # Slightly below top surface

entry_ras = nib.affines.apply_affine(affine, entry_voxel)
print(f"Suggested entry (RAS): {entry_ras}")

# Compute ideal trajectory parameters
trajectory_vector = target_ras - entry_ras
trajectory_length = np.linalg.norm(trajectory_vector)
# Angle from vertical (S axis)
if trajectory_length > 0:
    angle_from_vertical = np.degrees(np.arccos(abs(trajectory_vector[2]) / trajectory_length))
else:
    angle_from_vertical = 0

print(f"Trajectory length: {trajectory_length:.1f} mm")
print(f"Angle from vertical: {angle_from_vertical:.1f} degrees")

# Store target zone voxels for verification
target_coords = np.argwhere(target_mask)

# Save ground truth for verification
gt_data = {
    "sample_id": sample_id,
    "target_ras": target_ras.tolist(),
    "target_voxel": target_voxel.tolist(),
    "suggested_entry_ras": entry_ras.tolist(),
    "suggested_entry_voxel": entry_voxel.tolist(),
    "trajectory_length_mm": float(trajectory_length),
    "angle_from_vertical_deg": float(angle_from_vertical),
    "enhancing_voxel_count": int(enhancing_voxels),
    "edema_voxel_count": int(edema_voxels),
    "brain_bounds_voxel": brain_bounds,
    "affine": affine.tolist(),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "shape": list(seg_data.shape),
    "target_zone_sample_voxels": target_coords[::max(1, len(target_coords)//100)].tolist() if len(target_coords) > 0 else []
}

gt_path = os.path.join(gt_dir, f"{sample_id}_trajectory_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to {gt_path}")

# Save edema distance transform for trajectory verification
edema_dt_path = os.path.join(gt_dir, f"{sample_id}_edema_dt.npy")
np.save(edema_dt_path, edema_distance.astype(np.float32))
print(f"Edema distance transform saved to {edema_dt_path}")

# Also copy ground truth to /tmp for verifier access
import shutil
shutil.copy(gt_path, "/tmp/trajectory_ground_truth.json")
print("Ground truth copied to /tmp for verification")
PYEOF

export SAMPLE_ID GROUND_TRUTH_DIR

# Clean up any previous outputs
echo "Cleaning up previous outputs..."
rm -f "$BRATS_DIR/biopsy_target.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/biopsy_entry.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/biopsy_trajectory.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/trajectory_report.json" 2>/dev/null || true
rm -f /tmp/trajectory_task_result.json 2>/dev/null || true

# Close any running Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Slicer Python script to load all volumes
cat > /tmp/load_brats_trajectory.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"

# Define volumes to load with display names
volumes = [
    (f"{sample_id}_t1.nii.gz", "T1"),
    (f"{sample_id}_t1ce.nii.gz", "T1_Contrast"),
    (f"{sample_id}_t2.nii.gz", "T2"),
    (f"{sample_id}_flair.nii.gz", "FLAIR"),
]

print("Loading BraTS MRI volumes for trajectory planning...")
loaded_nodes = []

for filename, display_name in volumes:
    filepath = os.path.join(sample_dir, filename)
    if os.path.exists(filepath):
        print(f"  Loading {display_name} from {filepath}")
        node = slicer.util.loadVolume(filepath)
        if node:
            node.SetName(display_name)
            loaded_nodes.append(node)
            print(f"    Loaded: {node.GetName()}")
        else:
            print(f"    ERROR loading {filepath}")
    else:
        print(f"  WARNING: File not found: {filepath}")

print(f"Loaded {len(loaded_nodes)} volumes")

# Set up the views for trajectory planning
if loaded_nodes:
    # Make T1_Contrast the background volume (shows enhancing tumor - target)
    t1ce_node = slicer.util.getNode("T1_Contrast")
    t2_node = slicer.util.getNode("T2")
    
    # Set slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceCompositeNode = sliceWidget.sliceLogic().GetSliceCompositeNode()
        
        # T1ce as background (shows tumor target)
        if t1ce_node:
            sliceCompositeNode.SetBackgroundVolumeID(t1ce_node.GetID())
        
        # T2 as foreground overlay (shows ventricles to avoid)
        if t2_node:
            sliceCompositeNode.SetForegroundVolumeID(t2_node.GetID())
            sliceCompositeNode.SetForegroundOpacity(0.3)

    # Switch to Four-Up view for better 3D planning
    slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

    # Reset views to show the data
    slicer.util.resetSliceViews()

    # Center on the data
    if t1ce_node:
        bounds = [0]*6
        t1ce_node.GetBounds(bounds)
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

print("")
print("=" * 60)
print("BraTS data loaded for STEREOTACTIC TRAJECTORY PLANNING")
print("=" * 60)
print("")
print("T1_Contrast (background): Shows ENHANCING TUMOR - your TARGET")
print("T2 (overlay 30%): Shows VENTRICLES - AVOID these!")
print("")
print("Instructions:")
print("  1. Identify the bright enhancing tumor on T1_Contrast")
print("  2. Place a fiducial at the tumor center (biopsy TARGET)")
print("  3. Check T2 to see ventricle locations")
print("  4. Place entry fiducial SUPERIOR to target, avoiding ventricles")
print("  5. Create a line markup for the trajectory")
print("  6. Save markups and create trajectory_report.json")
print("")
PYEOF

# Launch Slicer with the Python script
echo "Launching 3D Slicer with BraTS volumes..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brats_trajectory.py > /tmp/slicer_launch.log 2>&1 &

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

# Wait for volumes to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/trajectory_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Stereotactic Brain Biopsy Trajectory Planning"
echo "====================================================="
echo ""
echo "Plan a safe stereotactic biopsy trajectory to sample the brain tumor."
echo ""
echo "MRI sequences loaded:"
echo "  - T1_Contrast: Shows enhancing tumor (BIOPSY TARGET)"
echo "  - T2: Shows ventricles (MUST AVOID)"
echo "  - FLAIR/T1: Anatomical reference"
echo ""
echo "Required outputs:"
echo "  1. ~/Documents/SlicerData/BraTS/biopsy_target.mrk.json"
echo "  2. ~/Documents/SlicerData/BraTS/biopsy_entry.mrk.json"
echo "  3. ~/Documents/SlicerData/BraTS/biopsy_trajectory.mrk.json"
echo "  4. ~/Documents/SlicerData/BraTS/trajectory_report.json"
echo ""