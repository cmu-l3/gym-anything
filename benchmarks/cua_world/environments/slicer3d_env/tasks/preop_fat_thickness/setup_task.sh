#!/bin/bash
echo "=== Setting up Pre-operative Fat Thickness Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Prepare AMOS data (downloads real data or generates synthetic)
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

# Calculate ground truth fat thickness
echo "Calculating ground truth fat thickness..."
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

case_id = "$CASE_ID"
amos_dir = "$AMOS_DIR"
gt_dir = "$GROUND_TRUTH_DIR"

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")

# Ensure ground truth directory exists
os.makedirs(gt_dir, exist_ok=True)

if not os.path.exists(ct_path):
    print("WARNING: CT not found, using default ground truth")
    gt_data = {
        "case_id": case_id,
        "fat_thickness_mm": 35.0,
        "vertebral_level": "L3",
        "measurement_slice": 50,
        "surgical_category": "Average"
    }
else:
    ct_nii = nib.load(ct_path)
    ct_data = ct_nii.get_fdata()
    spacing = ct_nii.header.get_zooms()[:3]
    
    print(f"CT shape: {ct_data.shape}, spacing: {spacing}")
    
    # Find umbilical level (approximately middle of volume for abdominal CT)
    mid_slice = ct_data.shape[2] // 2
    
    # Analyze anterior midline at this slice
    axial = ct_data[:, :, mid_slice]
    mid_x = axial.shape[0] // 2
    
    # Profile along anterior direction (y-axis)
    # In standard orientation, low y values are anterior
    anterior_profile = axial[mid_x, :]
    
    # Find skin surface (transition from air ~-1000 to tissue ~0)
    skin_idx = None
    for i in range(len(anterior_profile) - 1):
        if anterior_profile[i] < -500 and anterior_profile[i+1] > -200:
            skin_idx = i + 1
            break
    
    # Find muscle layer (transition from fat ~-100 to muscle ~40-60)
    muscle_idx = None
    if skin_idx:
        for i in range(skin_idx, min(skin_idx + 150, len(anterior_profile) - 1)):
            # Fat is typically -100 to -50 HU, muscle is 30-60 HU
            if anterior_profile[i] < 0 and anterior_profile[i+1] > 20:
                muscle_idx = i
                break
    
    if skin_idx and muscle_idx:
        fat_thickness_pixels = muscle_idx - skin_idx
        fat_thickness_mm = float(fat_thickness_pixels * spacing[1])
        print(f"Detected fat thickness: {fat_thickness_mm:.1f} mm ({fat_thickness_pixels} pixels)")
    else:
        # Fallback for synthetic data - estimate from body dimensions
        print("Could not detect fat layer boundaries, using estimate")
        fat_thickness_mm = 35.0
    
    # Clamp to reasonable range
    fat_thickness_mm = max(10.0, min(fat_thickness_mm, 100.0))
    
    # Determine surgical category
    if fat_thickness_mm < 20:
        category = "Thin"
    elif fat_thickness_mm < 40:
        category = "Average"
    elif fat_thickness_mm < 60:
        category = "Thick"
    else:
        category = "Very Thick"
    
    # Estimate vertebral level based on slice position
    z_fraction = mid_slice / ct_data.shape[2]
    if z_fraction < 0.3:
        vert_level = "L4"
    elif z_fraction < 0.5:
        vert_level = "L3"
    elif z_fraction < 0.7:
        vert_level = "L2"
    else:
        vert_level = "L1"
    
    gt_data = {
        "case_id": case_id,
        "fat_thickness_mm": round(fat_thickness_mm, 1),
        "vertebral_level": vert_level,
        "measurement_slice": int(mid_slice),
        "measurement_z_mm": float(mid_slice * spacing[2]),
        "surgical_category": category,
        "spacing_mm": [float(s) for s in spacing],
        "volume_shape": list(ct_data.shape)
    }

gt_path = os.path.join(gt_dir, f"{case_id}_fat_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved: {gt_path}")
print(f"  Fat thickness: {gt_data['fat_thickness_mm']} mm")
print(f"  Vertebral level: {gt_data['vertebral_level']}")
print(f"  Category: {gt_data['surgical_category']}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_fat_gt.json" ]; then
    echo "ERROR: Ground truth not created!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous results
echo "Cleaning up previous results..."
rm -f "$AMOS_DIR/fat_thickness_measurement.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/surgical_planning_report.json" 2>/dev/null || true
rm -f /tmp/fat_task_result.json 2>/dev/null || true

# Create a Slicer Python script to load the CT with appropriate window
cat > /tmp/load_amos_fat.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading abdominal CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set default soft tissue window/level for fat visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window - good for distinguishing fat from muscle
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on the data - position at approximate umbilical level
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2  # Middle of z-range
    
    # Set all views to center
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center_z)  # Axial - set to middle
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])  # Coronal
        else:
            sliceNode.SetSliceOffset(center[0])  # Sagittal
    
    print(f"CT loaded with soft tissue window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Centered at z={center_z:.1f}mm (approximate umbilical level)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for fat thickness measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
export CT_FILE CASE_ID
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_amos_fat.py > /tmp/slicer_launch.log 2>&1 &

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
echo "Capturing initial screenshot..."
take_screenshot /tmp/fat_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/fat_initial.png ]; then
    SIZE=$(stat -c %s /tmp/fat_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Pre-operative Subcutaneous Fat Thickness Assessment"
echo "==========================================================="
echo ""
echo "A surgeon is planning an open cholecystectomy and needs to assess"
echo "the abdominal wall fat thickness at the planned incision site."
echo ""
echo "Your task:"
echo "  1. Navigate to the umbilical level (L3-L4 vertebral body)"
echo "  2. On an axial slice, measure the anterior midline fat thickness"
echo "  3. Measure from skin surface to anterior rectus sheath (muscle)"
echo "  4. Use the Markups ruler tool for the measurement"
echo ""
echo "Clinical classification:"
echo "  - Thin (<20mm): Standard instruments, low SSI risk"
echo "  - Average (20-40mm): Standard instruments, moderate SSI risk"
echo "  - Thick (40-60mm): Consider longer instruments, elevated SSI risk"
echo "  - Very Thick (>60mm): Bariatric instruments required, high SSI risk"
echo ""
echo "Save your outputs:"
echo "  - Measurement: ~/Documents/SlicerData/AMOS/fat_thickness_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/surgical_planning_report.json"
echo ""
echo "Report JSON should contain:"
echo "  - fat_thickness_mm: your measurement"
echo "  - vertebral_level: e.g., \"L3\""
echo "  - surgical_category: \"Thin\", \"Average\", \"Thick\", or \"Very Thick\""
echo ""