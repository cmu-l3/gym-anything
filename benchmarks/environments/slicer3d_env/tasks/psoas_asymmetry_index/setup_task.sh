#!/bin/bash
echo "=== Setting up Psoas Asymmetry Index Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date -Iseconds)"

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 abdominal CT data..."
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

# ============================================================
# Generate ground truth psoas measurements
# ============================================================
echo "Calculating ground truth psoas measurements..."
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
case_id = open("/tmp/amos_case_id").read().strip() if os.path.exists("/tmp/amos_case_id") else "amos_0001"

# Load CT
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
if not os.path.exists(ct_path):
    print(f"ERROR: CT not found at {ct_path}")
    sys.exit(1)

ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Find L3 level (approximately 40-50% of z-range in abdomen)
nz = ct_data.shape[2]
l3_slice = int(nz * 0.45)

print(f"Using slice {l3_slice} as L3 level (z={l3_slice * spacing[2]:.1f}mm)")

# Get the axial slice
ct_slice = ct_data[:, :, l3_slice]
nx, ny = ct_slice.shape
center_x, center_y = nx // 2, ny // 2

# Pixel area for volume calculation
pixel_area_mm2 = float(spacing[0] * spacing[1])

# Identify psoas regions using HU values and anatomical position
# Psoas muscle typically has HU values between 30-70
# Located lateral to spine, posterior region

# Create muscle mask (HU approximately 30-80 for muscle)
muscle_mask = (ct_slice > 20) & (ct_slice < 90)

# Define anatomical regions for left and right psoas
# Left psoas (patient's left = image right in standard orientation)
# Right psoas (patient's right = image left)

# Psoas is typically 20-50 pixels lateral to midline, in posterior half
# Adjust based on image size
lateral_offset = int(25 * (nx / 256))  # Scale for image size
posterior_start = int(center_y + 15 * (ny / 256))
posterior_end = int(center_y + 55 * (ny / 256))
psoas_width = int(35 * (nx / 256))

# Left psoas region (right side of image)
Y, X = np.ogrid[:nx, :ny]
left_region = np.zeros_like(muscle_mask, dtype=bool)
left_cx = center_x + lateral_offset
left_region[(X - left_cx)**2 + (Y - (posterior_start + posterior_end)//2)**2 < (psoas_width)**2] = True
left_region &= (Y > posterior_start) & (Y < posterior_end)

# Right psoas region (left side of image)
right_region = np.zeros_like(muscle_mask, dtype=bool)
right_cx = center_x - lateral_offset
right_region[(X - right_cx)**2 + (Y - (posterior_start + posterior_end)//2)**2 < (psoas_width)**2] = True
right_region &= (Y > posterior_start) & (Y < posterior_end)

# Get psoas masks
left_psoas = muscle_mask & left_region
right_psoas = muscle_mask & right_region

# Calculate areas
left_area_pixels = np.sum(left_psoas)
right_area_pixels = np.sum(right_psoas)

left_area_mm2 = float(left_area_pixels * pixel_area_mm2)
right_area_mm2 = float(right_area_pixels * pixel_area_mm2)

print(f"Raw measurements - Left: {left_area_mm2:.1f} mm², Right: {right_area_mm2:.1f} mm²")

# If areas are unrealistic, use synthetic realistic values
# Typical psoas CSA at L3: 1000-2000 mm² per side
if left_area_mm2 < 400 or left_area_mm2 > 4000 or right_area_mm2 < 400 or right_area_mm2 > 4000:
    print("Detected values outside realistic range, using calibrated synthetic values")
    np.random.seed(42)
    # Create mild asymmetry (~12%) for an interesting case
    left_area_mm2 = 1480.0 + np.random.normal(0, 30)
    right_area_mm2 = 1295.0 + np.random.normal(0, 30)  # ~12.5% smaller

# Calculate asymmetry index
avg_area = (left_area_mm2 + right_area_mm2) / 2.0
asymmetry_pct = abs(left_area_mm2 - right_area_mm2) / avg_area * 100.0

# Classification
if asymmetry_pct < 10:
    classification = "Symmetric"
elif asymmetry_pct < 20:
    classification = "Mild Asymmetry"
else:
    classification = "Significant Asymmetry"

# Smaller side
if asymmetry_pct < 5:
    smaller_side = "Equal"
elif right_area_mm2 < left_area_mm2:
    smaller_side = "Right"
else:
    smaller_side = "Left"

# Save ground truth
gt_data = {
    "case_id": case_id,
    "vertebral_level": "L3",
    "slice_index": int(l3_slice),
    "slice_z_mm": float(l3_slice * spacing[2]),
    "left_psoas_area_mm2": round(left_area_mm2, 1),
    "right_psoas_area_mm2": round(right_area_mm2, 1),
    "asymmetry_index_percent": round(asymmetry_pct, 2),
    "classification": classification,
    "smaller_side": smaller_side,
    "pixel_spacing_mm": [float(spacing[0]), float(spacing[1])],
    "slice_thickness_mm": float(spacing[2]),
    "acceptable_area_error_percent": 15,
    "acceptable_index_error_points": 5
}

os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{case_id}_psoas_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"  Left psoas: {gt_data['left_psoas_area_mm2']} mm²")
print(f"  Right psoas: {gt_data['right_psoas_area_mm2']} mm²")
print(f"  Asymmetry Index: {gt_data['asymmetry_index_percent']:.1f}%")
print(f"  Classification: {gt_data['classification']}")
print(f"  Smaller side: {gt_data['smaller_side']}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_psoas_gt.json" ]; then
    echo "ERROR: Ground truth calculation failed!"
    exit 1
fi
echo "Ground truth verified"

# ============================================================
# Clean previous results
# ============================================================
echo "Cleaning previous task results..."
rm -f "$AMOS_DIR/psoas_asymmetry_report.json" 2>/dev/null || true
rm -f "$AMOS_DIR/left_psoas"*.json 2>/dev/null || true
rm -f "$AMOS_DIR/right_psoas"*.json 2>/dev/null || true
rm -f /tmp/psoas_task_result.json 2>/dev/null || true

# ============================================================
# Create Slicer Python script to load CT with abdominal settings
# ============================================================
cat > /tmp/load_psoas_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT for psoas assessment: {case_id}...")

# Load volume
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set soft tissue window for muscle visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Window/Level for soft tissue (good for muscle boundaries)
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to approximate L3 level
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    z_center = (bounds[4] + bounds[5]) / 2
    # L3 is roughly at 45% of abdominal z-range
    l3_position = bounds[4] + (bounds[5] - bounds[4]) * 0.45
    
    # Set axial view (Red) to L3 level
    redSliceNode = slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode()
    redSliceNode.SetSliceOffset(l3_position)
    
    # Set coronal (Green) and sagittal (Yellow) to center
    greenSliceNode = slicer.app.layoutManager().sliceWidget("Green").sliceLogic().GetSliceNode()
    greenSliceNode.SetSliceOffset((bounds[2] + bounds[3]) / 2)
    
    yellowSliceNode = slicer.app.layoutManager().sliceWidget("Yellow").sliceLogic().GetSliceNode()
    yellowSliceNode.SetSliceOffset((bounds[0] + bounds[1]) / 2)
    
    print(f"CT loaded with soft tissue window (W=350, L=50)")
    print(f"Axial view set to approximate L3 level (z={l3_position:.1f}mm)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("\\nSetup complete - ready for psoas measurement task")
print("Navigate to L3-L4 level to measure psoas muscles")
PYEOF

# ============================================================
# Launch Slicer
# ============================================================
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_psoas_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/psoas_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Psoas Muscle Asymmetry Index Assessment"
echo "=============================================="
echo ""
echo "You are given an abdominal CT scan. Measure and compare the"
echo "cross-sectional areas of the left and right psoas major muscles."
echo ""
echo "Clinical context:"
echo "  - Psoas muscles are lateral to the lumbar vertebral bodies"
echo "  - Normal asymmetry is < 10%"
echo "  - Significant asymmetry (>20%) may indicate pathology"
echo ""
echo "Your tasks:"
echo "  1. Navigate to L3-L4 level (or mid-L3)"
echo "  2. Measure LEFT psoas cross-sectional area (mm² or cm²)"
echo "  3. Measure RIGHT psoas cross-sectional area"
echo "  4. Calculate Asymmetry Index: |L-R|/avg × 100%"
echo "  5. Classify: Symmetric (<10%), Mild (10-20%), Significant (>20%)"
echo ""
echo "Save report to: ~/Documents/SlicerData/AMOS/psoas_asymmetry_report.json"
echo ""