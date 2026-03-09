#!/bin/bash
echo "=== Setting up WHO Bidimensional Measurement Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

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
T1CE_FILE="$SAMPLE_DIR/${SAMPLE_ID}_t1ce.nii.gz"

echo "Using sample: $SAMPLE_ID"

# Verify T1ce file exists
if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    exit 1
fi
echo "T1ce volume found: $T1CE_FILE"

# Verify ground truth segmentation exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Compute ground truth WHO measurements from segmentation
echo "Computing ground truth WHO measurements..."
python3 << PYEOF
import os
import json
import numpy as np

# Ensure dependencies
try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
    import nibabel as nib

from scipy.ndimage import binary_erosion
from scipy.spatial.distance import cdist

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
output_path = os.path.join(gt_dir, f"{sample_id}_who_gt.json")

print(f"Loading segmentation: {seg_path}")
seg = nib.load(seg_path)
data = seg.get_fdata().astype(np.int32)
spacing = seg.header.get_zooms()[:3]

print(f"Segmentation shape: {data.shape}")
print(f"Voxel spacing (mm): {spacing}")
print(f"Labels present: {np.unique(data)}")

# Find enhancing tumor (label 4) - this is what shows up bright on T1ce
enhancing = (data == 4)
enhancing_voxels = np.sum(enhancing)
print(f"Enhancing tumor voxels: {enhancing_voxels}")

# If no enhancing tumor, fall back to whole tumor
if enhancing_voxels < 100:
    print("Insufficient enhancing tumor, using whole tumor (labels 1,2,4)")
    tumor_mask = (data > 0)
else:
    tumor_mask = enhancing

# Find slice with maximum tumor area
max_area = 0
max_slice = 0
for z in range(data.shape[2]):
    area = np.sum(tumor_mask[:, :, z])
    if area > max_area:
        max_area = area
        max_slice = z

print(f"Maximum tumor area at slice {max_slice} ({max_area} voxels)")

# Get tumor boundary on max slice
slice_mask = tumor_mask[:, :, max_slice]

if not np.any(slice_mask):
    print("ERROR: No tumor found on selected slice!")
    gt_data = {
        "sample_id": sample_id,
        "error": "No tumor found",
        "measurement_slice": 0,
        "longest_diameter_mm": 0,
        "perpendicular_diameter_mm": 0,
        "bidimensional_product_mm2": 0,
    }
else:
    # Find boundary points
    interior = binary_erosion(slice_mask)
    boundary = slice_mask & ~interior
    boundary_points = np.argwhere(boundary)
    
    if len(boundary_points) < 3:
        # Use all tumor points if boundary is too small
        boundary_points = np.argwhere(slice_mask)
    
    print(f"Boundary points: {len(boundary_points)}")
    
    # Convert to mm coordinates
    boundary_mm = boundary_points * np.array([spacing[0], spacing[1]])
    
    # Find longest diameter using pairwise distances
    if len(boundary_mm) > 1:
        distances = cdist(boundary_mm, boundary_mm)
        max_idx = np.unravel_index(np.argmax(distances), distances.shape)
        d1_mm = distances[max_idx[0], max_idx[1]]
        p1, p2 = boundary_mm[max_idx[0]], boundary_mm[max_idx[1]]
        
        # Direction of longest diameter
        d1_vec = p2 - p1
        d1_norm = np.linalg.norm(d1_vec)
        d1_vec = d1_vec / d1_norm if d1_norm > 0 else np.array([1, 0])
        
        # Perpendicular direction
        perp_vec = np.array([-d1_vec[1], d1_vec[0]])
        
        # Project all boundary points onto perpendicular direction
        # D2 is the maximum extent in the perpendicular direction
        centroid = np.mean(boundary_mm, axis=0)
        projections = np.dot(boundary_mm - centroid, perp_vec)
        d2_mm = np.max(projections) - np.min(projections)
    else:
        d1_mm = 0
        d2_mm = 0
    
    # Calculate bidimensional product
    product = d1_mm * d2_mm
    
    print(f"Ground truth measurements:")
    print(f"  D1 (longest diameter): {d1_mm:.1f} mm")
    print(f"  D2 (perpendicular diameter): {d2_mm:.1f} mm")
    print(f"  Bidimensional product: {product:.1f} mm²")
    print(f"  Measurement slice: {max_slice}")
    
    gt_data = {
        "sample_id": sample_id,
        "measurement_slice": int(max_slice),
        "longest_diameter_mm": float(round(d1_mm, 1)),
        "perpendicular_diameter_mm": float(round(d2_mm, 1)),
        "bidimensional_product_mm2": float(round(product, 1)),
        "slice_range_acceptable": [int(max_slice - 3), int(max_slice + 3)],
        "voxel_spacing_mm": [float(s) for s in spacing],
        "total_slices": int(data.shape[2])
    }

# Save ground truth
with open(output_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {output_path}")
PYEOF

# Clean any previous agent outputs
echo "Cleaning previous outputs..."
rm -f "$BRATS_DIR/who_measurements.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/who_report.json" 2>/dev/null || true

# Create Slicer Python script to load T1ce with proper setup
cat > /tmp/load_t1ce_for_who.py << 'PYEOF'
import slicer
import os

t1ce_path = os.environ.get("T1CE_FILE", "")
sample_id = os.environ.get("SAMPLE_ID", "BraTS")

print(f"Loading T1ce for WHO measurement task...")
print(f"File: {t1ce_path}")

if os.path.exists(t1ce_path):
    volume_node = slicer.util.loadVolume(t1ce_path)
    if volume_node:
        volume_node.SetName("T1_Contrast")
        
        # Set appropriate window/level for brain tumor visualization
        displayNode = volume_node.GetDisplayNode()
        if displayNode:
            # Window/level optimized for contrast-enhanced MRI
            displayNode.SetWindow(600)
            displayNode.SetLevel(300)
            displayNode.SetAutoWindowLevel(False)
        
        # Set as background in all slice views
        for color in ["Red", "Green", "Yellow"]:
            sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
            sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
        
        # Reset and center views
        slicer.util.resetSliceViews()
        
        # Center on data
        bounds = [0]*6
        volume_node.GetBounds(bounds)
        center_z = (bounds[4] + bounds[5])/2
        
        # Set Red slice (axial) to center - this is where measurements should be made
        redSlice = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
        redSlice.GetSliceNode().SetSliceOffset(center_z)
        
        print(f"T1ce loaded successfully")
        print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
        print(f"Centered at z={center_z:.1f}")
    else:
        print("ERROR: Could not load T1ce volume")
else:
    print(f"ERROR: File not found: {t1ce_path}")

print("\nTask ready: Measure tumor using WHO bidimensional criteria")
print("Use the Red (axial) view to find the slice with maximum tumor extent")
print("Place two perpendicular ruler measurements for D1 and D2")
PYEOF

# Export environment variables for the Python script
export T1CE_FILE SAMPLE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the T1ce volume
echo "Launching 3D Slicer with T1ce MRI..."
sudo -u ga DISPLAY=:1 T1CE_FILE="$T1CE_FILE" SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/load_t1ce_for_who.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
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
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/who_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: WHO Bidimensional Tumor Measurement"
echo "=========================================="
echo ""
echo "The T1-contrast enhanced MRI is loaded. The tumor appears as"
echo "a bright (enhancing) region in the brain."
echo ""
echo "Your goal:"
echo "  1. Navigate in the Red (axial) view to find the slice"
echo "     with maximum tumor cross-section"
echo "  2. Use Markups > Line to place TWO ruler measurements:"
echo "     - D1: longest diameter through the tumor"
echo "     - D2: longest diameter PERPENDICULAR to D1"
echo "  3. The two lines MUST be at 90° to each other"
echo ""
echo "Save your outputs:"
echo "  - Markups: ~/Documents/SlicerData/BraTS/who_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/who_report.json"
echo ""
echo "Report JSON should contain:"
echo "  - longest_diameter_mm"
echo "  - perpendicular_diameter_mm"
echo "  - bidimensional_product_mm2"
echo "  - measurement_slice"
echo ""