#!/bin/bash
echo "=== Setting up Visceral Fat Quantification Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data or generates synthetic if needed)
echo "Preparing AMOS 2022 data..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
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

# Create ground truth fat analysis if it doesn't exist
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_fat_gt.json" ]; then
    echo "Computing ground truth fat quantification..."
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

try:
    from scipy import ndimage
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy import ndimage

ct_path = "$CT_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
case_id = "$CASE_ID"

print(f"Loading CT: {ct_path}")
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Find L4-L5 level (approximately 40-50% from bottom of abdominal volume)
# This is a simplification - in real data would use vertebral detection
nz = ct_data.shape[2]
l4_l5_slice = int(nz * 0.45)  # Approximate L4-L5 level

print(f"Estimated L4-L5 level at slice {l4_l5_slice}")

# Extract the slice
slice_data = ct_data[:, :, l4_l5_slice]

# Fat HU threshold: -190 to -30
fat_mask = (slice_data >= -190) & (slice_data <= -30)

# Detect body contour (separate from air)
body_mask = slice_data > -500  # Anything denser than air

# Label connected components in body mask
labeled_body, num_features = ndimage.label(body_mask)
if num_features > 0:
    # Find largest connected component (the body)
    component_sizes = ndimage.sum(body_mask, labeled_body, range(1, num_features + 1))
    largest_component = np.argmax(component_sizes) + 1
    body_mask = (labeled_body == largest_component)

# Approximate separation of SAT and VAT:
# SAT is fat in the outer ring (between skin and muscle fascia)
# VAT is fat inside the abdominal cavity

# Simple approach: erode body mask to get approximate inner boundary
# SAT is fat between body boundary and eroded boundary
# VAT is fat inside eroded boundary

struct = ndimage.generate_binary_structure(2, 1)
eroded_body = ndimage.binary_erosion(body_mask, struct, iterations=15)

# SAT: fat outside eroded boundary but inside body
sat_mask = fat_mask & body_mask & ~eroded_body

# VAT: fat inside eroded boundary
vat_mask = fat_mask & eroded_body

# Calculate areas
pixel_area_mm2 = float(spacing[0] * spacing[1])
pixel_area_cm2 = pixel_area_mm2 / 100.0

sat_area_cm2 = float(np.sum(sat_mask) * pixel_area_cm2)
vat_area_cm2 = float(np.sum(vat_mask) * pixel_area_cm2)
total_fat_cm2 = sat_area_cm2 + vat_area_cm2

# Calculate ratio
if sat_area_cm2 > 0:
    vat_sat_ratio = vat_area_cm2 / sat_area_cm2
else:
    vat_sat_ratio = 0.0

# Classify
if vat_sat_ratio < 0.4:
    classification = "Gynoid"
elif vat_sat_ratio <= 1.0:
    classification = "Intermediate"
else:
    classification = "Android"

# Approximate vertebral level based on position
z_fraction = l4_l5_slice / nz
if z_fraction < 0.3:
    vertebral_level = "L5-S1"
elif z_fraction < 0.45:
    vertebral_level = "L4-L5"
elif z_fraction < 0.55:
    vertebral_level = "L3-L4"
elif z_fraction < 0.65:
    vertebral_level = "L2-L3"
else:
    vertebral_level = "L1-L2"

gt_data = {
    "case_id": case_id,
    "measurement_level": "L4-L5",
    "ground_truth_slice_index": int(l4_l5_slice),
    "slice_tolerance": 3,
    "spacing_mm": [float(s) for s in spacing],
    "pixel_area_cm2": pixel_area_cm2,
    "sat_area_cm2": round(sat_area_cm2, 2),
    "vat_area_cm2": round(vat_area_cm2, 2),
    "total_fat_area_cm2": round(total_fat_cm2, 2),
    "vat_sat_ratio": round(vat_sat_ratio, 3),
    "fat_distribution": classification,
    "physiological_ranges": {
        "sat_typical_range_cm2": [50, 600],
        "vat_typical_range_cm2": [30, 400],
        "vat_sat_ratio_gynoid": [0, 0.4],
        "vat_sat_ratio_intermediate": [0.4, 1.0],
        "vat_sat_ratio_android": [1.0, 5.0]
    }
}

gt_path = os.path.join(gt_dir, f"{case_id}_fat_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  L4-L5 slice: {l4_l5_slice}")
print(f"  SAT area: {sat_area_cm2:.1f} cm²")
print(f"  VAT area: {vat_area_cm2:.1f} cm²")
print(f"  VAT/SAT ratio: {vat_sat_ratio:.3f}")
print(f"  Classification: {classification}")
PYEOF
fi

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_fat_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state and timestamps
rm -f /tmp/fat_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/fat_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/fat_analysis_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Save case ID for export script
echo "$CASE_ID" > /tmp/fat_task_case_id.txt

# Create a Slicer Python script to load the CT with appropriate window
cat > /tmp/load_ct_for_fat.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT for fat quantification: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")

    # Set soft tissue window/level (good for fat visualization)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Wide window to see fat contrast
        displayNode.SetWindow(500)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Center on the approximate L4-L5 level
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            # Start near L4-L5 level (approximately 45% from inferior)
            z_range = bounds[5] - bounds[4]
            l4_l5_z = bounds[4] + z_range * 0.45
            sliceNode.SetSliceOffset(l4_l5_z)
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

    print(f"CT loaded with soft tissue window (W=500, L=50)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Positioned near approximate L4-L5 level")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for fat quantification task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_ct_for_fat.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/fat_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Visceral Adiposity Quantification"
echo "========================================"
echo ""
echo "You are given an abdominal CT scan for body composition analysis."
echo ""
echo "Your goal:"
echo "  1. Navigate to the L4-L5 intervertebral disc level"
echo "     (between 4th and 5th lumbar vertebrae)"
echo "  2. Create two segments at this level:"
echo "     - SAT: Subcutaneous fat (between skin and muscle)"
echo "     - VAT: Visceral fat (inside abdominal cavity)"
echo "  3. Use fat HU threshold: -190 to -30 HU"
echo "  4. Calculate areas using Segment Statistics"
echo "  5. Compute VAT/SAT ratio and classify:"
echo "     - Gynoid: ratio < 0.4"
echo "     - Intermediate: ratio 0.4 - 1.0"
echo "     - Android: ratio > 1.0"
echo ""
echo "Save outputs to:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/fat_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/AMOS/fat_analysis_report.json"
echo ""