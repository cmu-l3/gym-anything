#!/bin/bash
echo "=== Setting up Carinal Angle Measurement Task ==="

source /workspace/scripts/task_utils.sh

AIRWAY_DIR="/home/ga/Documents/SlicerData/Airway"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SAMPLE_DATA_DIR="/home/ga/Documents/SlicerData/SampleData"

# Create directories
mkdir -p "$AIRWAY_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous outputs
rm -f "$AIRWAY_DIR/carinal_angle.mrk.json" 2>/dev/null || true
rm -f "$AIRWAY_DIR/carinal_report.json" 2>/dev/null || true
rm -f /tmp/carinal_task_result.json 2>/dev/null || true

# ============================================================
# Prepare chest CT data
# ============================================================
echo "Preparing chest CT data..."

CT_FILE=""
CT_SOURCE=""

# Option 1: Use CTChest sample if available
if [ -f "$SAMPLE_DATA_DIR/CTChest.nrrd" ]; then
    CT_FILE="$SAMPLE_DATA_DIR/CTChest.nrrd"
    CT_SOURCE="CTChest_sample"
    echo "Using CTChest sample data"
# Option 2: Try to download LIDC sample
elif [ ! -f "$AIRWAY_DIR/chest_ct.nii.gz" ]; then
    echo "Downloading chest CT sample for airway analysis..."
    
    # Try to get CTChest from Slicer sample data
    cd "$SAMPLE_DATA_DIR"
    if curl -L -o CTChest.nrrd --connect-timeout 30 --max-time 180 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/4507b664690840abb6cb9af2d919377ffc4ef75b167cb6fd0f747befdb12e38e" 2>/dev/null; then
        if [ -f CTChest.nrrd ] && [ $(stat -c%s CTChest.nrrd 2>/dev/null || echo 0) -gt 10000000 ]; then
            CT_FILE="$SAMPLE_DATA_DIR/CTChest.nrrd"
            CT_SOURCE="CTChest_downloaded"
            echo "Downloaded CTChest sample successfully"
        fi
    fi
fi

# Fallback: Generate synthetic chest CT with known airway geometry
if [ -z "$CT_FILE" ] || [ ! -f "$CT_FILE" ]; then
    echo "Generating synthetic chest CT with airways..."
    
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

airway_dir = "/home/ga/Documents/SlicerData/Airway"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Create synthetic chest CT with realistic airways
# Dimensions: 512x512x200 (typical chest CT)
nx, ny, nz = 256, 256, 150
spacing = (0.7, 0.7, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize with lung tissue HU (-500 to -900)
ct_data = np.random.normal(-700, 50, (nx, ny, nz)).astype(np.int16)

# Create body outline
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Chest wall (soft tissue ~40 HU)
body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (90**2)) <= 1.0
chest_wall = ((X - center_x)**2 / (110**2) + (Y - center_y)**2 / (100**2)) <= 1.0
wall_only = chest_wall & ~body_mask

for z in range(nz):
    ct_data[:, :, z][wall_only] = np.random.normal(40, 15, np.sum(wall_only)).astype(np.int16)
    ct_data[:, :, z][~chest_wall] = -1000  # Air outside body

# Create trachea (air-filled tube, -1000 HU)
# Trachea runs from top down to carina at approximately z=75 (middle of volume)
trachea_cx, trachea_cy = center_x, center_y - 40  # Anterior to spine
trachea_radius = 12 / spacing[0]  # ~12mm diameter trachea

carina_z = 75  # Slice where bifurcation occurs
carina_z_mm = carina_z * spacing[2]

# Draw trachea above carina
for z in range(carina_z, nz):
    trachea_mask = ((X - trachea_cx)**2 + (Y - trachea_cy)**2) <= trachea_radius**2
    ct_data[:, :, z][trachea_mask & body_mask] = -1000

# Create main bronchi below carina
# Carinal angle will be ~72 degrees (normal range)
# Right bronchus: ~25 degrees from vertical (steeper)
# Left bronchus: ~47 degrees from vertical (more horizontal)
carinal_angle_degrees = 72.0
right_angle_rad = np.radians(25)  # from vertical
left_angle_rad = np.radians(47)   # from vertical

bronchus_radius = 8 / spacing[0]  # ~8mm diameter main bronchi

for z in range(0, carina_z):
    distance_from_carina = (carina_z - z) * spacing[2]  # mm below carina
    
    # Right main bronchus (goes right and slightly anterior)
    right_offset_x = distance_from_carina * np.tan(right_angle_rad) / spacing[0]
    right_cx = trachea_cx + right_offset_x
    right_cy = trachea_cy
    
    # Left main bronchus (goes left and slightly anterior)  
    left_offset_x = distance_from_carina * np.tan(left_angle_rad) / spacing[0]
    left_cx = trachea_cx - left_offset_x
    left_cy = trachea_cy
    
    # Bronchi get slightly smaller as they branch
    current_radius = bronchus_radius * max(0.6, 1.0 - distance_from_carina/200)
    
    right_mask = ((X - right_cx)**2 + (Y - right_cy)**2) <= current_radius**2
    left_mask = ((X - left_cx)**2 + (Y - left_cy)**2) <= current_radius**2
    
    ct_data[:, :, z][right_mask & body_mask] = -1000
    ct_data[:, :, z][left_mask & body_mask] = -1000

# Add mediastinal structures (heart, great vessels)
# Heart (soft tissue)
heart_cx, heart_cy = center_x - 20, center_y - 20
for z in range(20, 70):
    z_factor = 1.0 - abs(z - 45) / 40.0
    heart_rx = 50 * z_factor
    heart_ry = 40 * z_factor
    if heart_rx > 0 and heart_ry > 0:
        heart_mask = ((X - heart_cx)**2 / (heart_rx**2) + (Y - heart_cy)**2 / (heart_ry**2)) <= 1.0
        ct_data[:, :, z][heart_mask & body_mask] = np.random.normal(45, 10, np.sum(heart_mask & body_mask)).astype(np.int16)

# Spine (bone, bright)
spine_cx, spine_cy = center_x, center_y + 70
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 15**2
    ct_data[:, :, z][spine_mask & body_mask] = np.random.normal(400, 80, np.sum(spine_mask & body_mask)).astype(np.int16)

# Save CT volume
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(airway_dir, "chest_ct.nii.gz")
nib.save(ct_nii, ct_path)
print(f"Synthetic chest CT saved to {ct_path}")

# Calculate and save ground truth
# Carina location in world coordinates
carina_world = [
    trachea_cx * spacing[0],
    trachea_cy * spacing[1],
    carina_z_mm
]

# Approximate vertebral level based on z position
# T5-T7 typically at 35-50% of thoracic height from top
total_z_mm = nz * spacing[2]
z_fraction = carina_z_mm / total_z_mm
if z_fraction > 0.6:
    vertebral_level = "T5"
elif z_fraction > 0.45:
    vertebral_level = "T6"
else:
    vertebral_level = "T7"

# Classification
if carinal_angle_degrees < 50:
    classification = "Narrowed"
elif carinal_angle_degrees > 100:
    classification = "Widened"
else:
    classification = "Normal"

ground_truth = {
    "carinal_angle_degrees": carinal_angle_degrees,
    "right_bronchus_angle_from_vertical": 25.0,
    "left_bronchus_angle_from_vertical": 47.0,
    "carina_position_voxel": [int(trachea_cx), int(trachea_cy), carina_z],
    "carina_position_mm": carina_world,
    "carina_z_mm": carina_z_mm,
    "vertebral_level": vertebral_level,
    "classification": classification,
    "image_spacing_mm": list(spacing),
    "image_dimensions": [nx, ny, nz],
    "data_source": "synthetic"
}

gt_path = os.path.join(gt_dir, "carinal_ground_truth.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"Carinal angle: {carinal_angle_degrees}°")
print(f"Classification: {classification}")
print(f"Vertebral level: {vertebral_level}")
PYEOF

    if [ -f "$AIRWAY_DIR/chest_ct.nii.gz" ]; then
        CT_FILE="$AIRWAY_DIR/chest_ct.nii.gz"
        CT_SOURCE="synthetic"
        echo "Synthetic chest CT generated successfully"
    fi
fi

# If we have real CT data, compute ground truth from it
if [ "$CT_SOURCE" = "CTChest_sample" ] || [ "$CT_SOURCE" = "CTChest_downloaded" ]; then
    echo "Computing ground truth for real CT data..."
    
    python3 << 'PYEOF'
import os
import json
import numpy as np

gt_dir = "/var/lib/slicer/ground_truth"
os.makedirs(gt_dir, exist_ok=True)

# For real CT, use literature-based normal values
# Actual measurement would require airway segmentation which is complex
# We provide reference values and allow reasonable tolerance

ground_truth = {
    "carinal_angle_degrees": 70.0,  # Normal average
    "right_bronchus_angle_from_vertical": 25.0,
    "left_bronchus_angle_from_vertical": 45.0,
    "vertebral_level": "T6",
    "classification": "Normal",
    "carina_z_mm": 0,  # Will be estimated from image
    "data_source": "CTChest_sample",
    "note": "Ground truth based on literature normal values; tolerance applied for real data"
}

gt_path = os.path.join(gt_dir, "carinal_ground_truth.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth reference saved to {gt_path}")
PYEOF
fi

# Verify CT file exists
if [ -z "$CT_FILE" ] || [ ! -f "$CT_FILE" ]; then
    echo "ERROR: No chest CT data available!"
    exit 1
fi

echo "CT file: $CT_FILE"
echo "Data source: $CT_SOURCE"

# Save CT path for export script
echo "$CT_FILE" > /tmp/carinal_ct_path.txt
echo "$CT_SOURCE" > /tmp/carinal_ct_source.txt

# Set permissions
chown -R ga:ga "$AIRWAY_DIR" 2>/dev/null || true
chmod -R 755 "$AIRWAY_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer with chest CT
# ============================================================

# Create Slicer Python script to load the CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"

print(f"Loading chest CT: {ct_path}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set lung window/level for airway visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Lung window: W=1500, L=-500 (good for airways)
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-500)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on data but NOT at carina level (agent must navigate)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Start at upper chest level (above carina)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        # Start at 70% of z-range (upper chest, above typical carina)
        upper_z = bounds[4] + 0.7 * (bounds[5] - bounds[4])
        if color == "Red":
            sliceNode.SetSliceOffset(upper_z)
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with lung window (W=1500, L=-500)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Agent should navigate inferiorly to find the carina")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete - ready for carinal angle measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/carinal_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Carinal Angle Measurement"
echo "================================"
echo ""
echo "A chest CT scan is loaded. Your goal is to measure the carinal angle"
echo "(the angle at the tracheal bifurcation)."
echo ""
echo "Instructions:"
echo "  1. Navigate inferiorly to find the carina (where trachea splits)"
echo "  2. Use Markups > Angle tool to place an angle measurement"
echo "  3. Place vertex at the bifurcation point"
echo "  4. Extend arms along right and left main bronchi"
echo "  5. Record the angle and classify:"
echo "     - Normal: 50-100°"
echo "     - Widened: >100°"
echo "     - Narrowed: <50°"
echo ""
echo "Save outputs:"
echo "  - Markup: ~/Documents/SlicerData/Airway/carinal_angle.mrk.json"
echo "  - Report: ~/Documents/SlicerData/Airway/carinal_report.json"
echo ""