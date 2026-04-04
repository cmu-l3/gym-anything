#!/bin/bash
echo "=== Setting up Optic Nerve Sheath Diameter Measurement Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date -Iseconds)"

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

# Find the T1 image (best for orbital visualization)
T1_FILE=""
if [ -f "$SAMPLE_DIR/${SAMPLE_ID}_t1.nii.gz" ]; then
    T1_FILE="$SAMPLE_DIR/${SAMPLE_ID}_t1.nii.gz"
elif [ -f "$BRATS_DIR/${SAMPLE_ID}_t1.nii.gz" ]; then
    T1_FILE="$BRATS_DIR/${SAMPLE_ID}_t1.nii.gz"
fi

if [ -z "$T1_FILE" ] || [ ! -f "$T1_FILE" ]; then
    echo "ERROR: T1 MRI volume not found"
    exit 1
fi
echo "T1 volume found: $T1_FILE"

# Create output directory
mkdir -p "$BRATS_DIR"
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true

# Clean any previous task outputs
rm -f "$BRATS_DIR/right_onsd.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/left_onsd.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/onsd_report.json" 2>/dev/null || true
rm -f /tmp/onsd_task_result.json 2>/dev/null || true

# Generate ground truth ONSD measurements
echo "Generating ground truth ONSD measurements..."
mkdir -p "$GROUND_TRUTH_DIR"

python3 << PYEOF
import os
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
t1_path = "$T1_FILE"
gt_dir = "$GROUND_TRUTH_DIR"

print(f"Loading T1 image: {t1_path}")

if os.path.exists(t1_path):
    img = nib.load(t1_path)
    data = img.get_fdata()
    affine = img.affine
    spacing = img.header.get_zooms()[:3]
    
    print(f"Volume shape: {data.shape}")
    print(f"Voxel spacing: {spacing}")
    
    # Brain MRI typically has orbits in inferior slices
    # Find approximate orbital level (lower 20-30% of volume in axial)
    nz = data.shape[2]
    orbital_slice = int(nz * 0.22)  # Approximate orbital level
    
    # Generate realistic ONSD values
    # Normal ONSD on MRI: 4.0-5.0mm, slightly asymmetric is normal
    np.random.seed(42 + hash(sample_id) % 1000)
    
    # Simulate normal ONSD values (most BraTS patients are adults without ICP issues)
    base_onsd = np.random.uniform(4.2, 4.8)
    right_onsd = round(base_onsd + np.random.uniform(-0.2, 0.2), 1)
    left_onsd = round(base_onsd + np.random.uniform(-0.2, 0.2), 1)
    mean_onsd = round((right_onsd + left_onsd) / 2, 2)
    
    # Determine ICP status based on threshold
    elevated_icp = mean_onsd > 5.0
    
    # Approximate orbital coordinates (center of orbits in world coordinates)
    center_voxel = np.array(data.shape) // 2
    
    # Right orbit (patient's right = radiological left) - approximately 25mm lateral
    right_orbit_offset_mm = np.array([25, -10, 0])  # lateral, anterior, superior
    right_orbit_voxel = center_voxel.copy()
    right_orbit_voxel[0] += int(right_orbit_offset_mm[0] / spacing[0])
    right_orbit_voxel[1] -= int(right_orbit_offset_mm[1] / spacing[1])
    right_orbit_voxel[2] = orbital_slice
    
    # Left orbit
    left_orbit_offset_mm = np.array([-25, -10, 0])
    left_orbit_voxel = center_voxel.copy()
    left_orbit_voxel[0] += int(left_orbit_offset_mm[0] / spacing[0])
    left_orbit_voxel[1] -= int(left_orbit_offset_mm[1] / spacing[1])
    left_orbit_voxel[2] = orbital_slice
    
    # Convert to world coordinates (RAS)
    right_world = nib.affines.apply_affine(affine, right_orbit_voxel)
    left_world = nib.affines.apply_affine(affine, left_orbit_voxel)
    
    gt_data = {
        "sample_id": sample_id,
        "right_onsd_mm": right_onsd,
        "left_onsd_mm": left_onsd,
        "mean_onsd_mm": mean_onsd,
        "elevated_icp": elevated_icp,
        "orbital_slice_index": int(orbital_slice),
        "right_orbit_coords_voxel": [int(x) for x in right_orbit_voxel],
        "left_orbit_coords_voxel": [int(x) for x in left_orbit_voxel],
        "right_orbit_coords_world": [float(x) for x in right_world],
        "left_orbit_coords_world": [float(x) for x in left_world],
        "voxel_spacing_mm": [float(s) for s in spacing],
        "volume_shape": list(data.shape),
        "tolerance_mm": 1.0,
        "icp_threshold_mm": 5.0,
        "measurement_protocol": "3mm posterior to globe, perpendicular to optic nerve"
    }
    
    gt_path = os.path.join(gt_dir, f"{sample_id}_onsd_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(gt_data, f, indent=2)
    
    print(f"Ground truth ONSD saved: {gt_path}")
    print(f"  Right ONSD: {right_onsd} mm")
    print(f"  Left ONSD: {left_onsd} mm")
    print(f"  Mean ONSD: {mean_onsd} mm")
    print(f"  Elevated ICP: {elevated_icp}")
    print(f"  Orbital slice: {orbital_slice}")
else:
    print(f"ERROR: Could not find T1 image at {t1_path}")
    # Create placeholder ground truth for testing
    gt_data = {
        "sample_id": sample_id,
        "right_onsd_mm": 4.5,
        "left_onsd_mm": 4.4,
        "mean_onsd_mm": 4.45,
        "elevated_icp": False,
        "tolerance_mm": 1.0,
        "icp_threshold_mm": 5.0
    }
    gt_path = os.path.join(gt_dir, f"{sample_id}_onsd_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(gt_data, f, indent=2)
    print(f"Created placeholder ground truth: {gt_path}")
PYEOF

# Set ground truth permissions (hidden from agent)
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Create Slicer Python script to load T1 and navigate to orbital level
cat > /tmp/load_brain_mri.py << PYEOF
import slicer
import os

t1_path = "$T1_FILE"
sample_id = "$SAMPLE_ID"

print(f"Loading brain MRI for ONSD measurement: {sample_id}")

# Load T1 volume
volume_node = slicer.util.loadVolume(t1_path)

if volume_node:
    volume_node.SetName("BrainMRI_T1")
    
    # Set appropriate brain window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(600)
        displayNode.SetLevel(300)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Get volume bounds and navigate to orbital level (inferior ~22% of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Calculate orbital level in the axial plane
    z_min = bounds[4]
    z_max = bounds[5]
    z_range = z_max - z_min
    orbital_z = z_min + (z_range * 0.22)  # Approximate orbital level
    
    # Set the Red (axial) slice to orbital level
    redSliceNode = slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode()
    redSliceNode.SetSliceOffset(orbital_z)
    
    # Center other views
    center_y = (bounds[2] + bounds[3]) / 2
    center_x = (bounds[0] + bounds[1]) / 2
    
    greenSliceNode = slicer.app.layoutManager().sliceWidget("Green").sliceLogic().GetSliceNode()
    greenSliceNode.SetSliceOffset(center_y)
    
    yellowSliceNode = slicer.app.layoutManager().sliceWidget("Yellow").sliceLogic().GetSliceNode()
    yellowSliceNode.SetSliceOffset(center_x)
    
    print(f"T1 MRI loaded successfully")
    print(f"  Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"  Navigated to approximate orbital level (z={orbital_z:.1f}mm)")
    print(f"  Window: 600, Level: 300 (brain soft tissue)")
else:
    print("ERROR: Could not load T1 MRI volume")

print("Setup complete - ready for ONSD measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_brain_mri.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/onsd_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Optic Nerve Sheath Diameter (ONSD) Measurement"
echo "======================================================"
echo ""
echo "A critical care physician suspects elevated intracranial pressure."
echo "Measure the optic nerve sheath diameter bilaterally."
echo ""
echo "Instructions:"
echo "  1. Navigate to axial slices at orbital level (scroll down in Red view)"
echo "  2. Locate both optic nerves posterior to the eyeballs"
echo "  3. Use Markups ruler tool to measure ONSD on each side"
echo "  4. Measure at 3mm posterior to the globe"
echo "  5. Measure perpendicular to the optic nerve (outer-to-outer)"
echo ""
echo "Clinical Threshold: Mean ONSD > 5.0mm suggests elevated ICP"
echo ""
echo "Save outputs:"
echo "  - Right ONSD: ~/Documents/SlicerData/BraTS/right_onsd.mrk.json"
echo "  - Left ONSD: ~/Documents/SlicerData/BraTS/left_onsd.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/onsd_report.json"
echo ""