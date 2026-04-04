#!/bin/bash
echo "=== Setting up Cardiac RV/LV Ratio Task ==="

source /workspace/scripts/task_utils.sh

CARDIAC_DIR="/home/ga/Documents/SlicerData/Cardiac"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create directories
mkdir -p "$CARDIAC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean up any previous attempt files
rm -f "$CARDIAC_DIR/rv_measurement.mrk.json" 2>/dev/null || true
rm -f "$CARDIAC_DIR/lv_measurement.mrk.json" 2>/dev/null || true
rm -f "$CARDIAC_DIR/cardiac_report.json" 2>/dev/null || true
rm -f /tmp/cardiac_task_result.json 2>/dev/null || true

# Generate synthetic cardiac CT data with known RV/LV dimensions
echo "Generating cardiac CT data with ground truth..."

python3 << 'PYEOF'
import numpy as np
import os
import json
import sys

# Try to import nibabel, install if not available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

# Use OS random for seed to vary between runs
np.random.seed(int.from_bytes(os.urandom(4), 'big') % 2**31)

cardiac_dir = "/home/ga/Documents/SlicerData/Cardiac"
gt_dir = "/var/lib/slicer/ground_truth"

os.makedirs(cardiac_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

# CT volume parameters
nx, ny, nz = 512, 512, 150
spacing = (0.7, 0.7, 3.0)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize with air (-1000 HU)
ct = np.full((nx, ny, nz), -1000, dtype=np.int16)

# Create coordinate grids
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# === Body contour (elliptical thorax) ===
body_a, body_b = 180, 130
body_mask = ((X - center_x)**2 / body_a**2 + (Y - center_y)**2 / body_b**2) <= 1

# Fill body with soft tissue (~40 HU with noise)
for z in range(nz):
    ct[:, :, z][body_mask] = np.random.normal(40, 12, np.sum(body_mask)).astype(np.int16)

# === Lungs (bilateral, air-filled) ===
lung_r_cx, lung_r_cy = center_x + 70, center_y - 10
lung_l_cx, lung_l_cy = center_x - 70, center_y - 10
lung_a, lung_b = 55, 85

for z in range(25, 125):
    z_factor = 1.0 - 0.35 * abs(z - 75) / 50
    
    lung_r = ((X - lung_r_cx)**2 / (lung_a * z_factor)**2 + 
              (Y - lung_r_cy)**2 / (lung_b * z_factor)**2) <= 1
    lung_l = ((X - lung_l_cx)**2 / (lung_a * z_factor)**2 + 
              (Y - lung_l_cy)**2 / (lung_b * z_factor)**2) <= 1
    
    ct[:, :, z][lung_r & body_mask] = np.random.normal(-850, 60, np.sum(lung_r & body_mask)).astype(np.int16)
    ct[:, :, z][lung_l & body_mask] = np.random.normal(-850, 60, np.sum(lung_l & body_mask)).astype(np.int16)

# === Spine (posterior) ===
spine_cx, spine_cy = center_x, center_y + 95
spine_r = 18

for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= spine_r**2
    ct[:, :, z][spine_mask] = np.random.normal(450, 70, np.sum(spine_mask)).astype(np.int16)

# === Heart with controllable RV/LV dimensions ===
# Randomize cardiac scenario
scenario = np.random.choice(['normal', 'borderline', 'dilated'], p=[0.4, 0.3, 0.3])

if scenario == 'normal':
    rv_diam_mm = np.random.uniform(26, 36)
    lv_diam_mm = np.random.uniform(42, 52)
elif scenario == 'borderline':
    rv_diam_mm = np.random.uniform(36, 44)
    lv_diam_mm = np.random.uniform(40, 48)
else:  # dilated
    rv_diam_mm = np.random.uniform(44, 56)
    lv_diam_mm = np.random.uniform(36, 46)

rv_ratio = rv_diam_mm / lv_diam_mm

# Convert to pixels
rv_radius_px = (rv_diam_mm / 2) / spacing[0]
lv_radius_px = (lv_diam_mm / 2) / spacing[0]

# Heart center (mediastinum, slightly left of midline)
heart_cx, heart_cy = center_x - 12, center_y + 15

# Optimal measurement slice (mid-heart, 4-chamber level)
optimal_slice = 72

# Calculate actual chamber centers at optimal slice
rv_cx_actual = heart_cx + 28
rv_cy_actual = heart_cy - 22
lv_cx_actual = heart_cx - 18
lv_cy_actual = heart_cy - 8

# Create cardiac chambers
for z in range(42, 102):
    z_factor = 1.0 - 0.5 * ((z - optimal_slice) / 30)**2
    if z_factor < 0.3:
        z_factor = 0.3
    
    # Left ventricle (posterior-lateral, elliptical, thick wall)
    lv_cx = heart_cx - 18
    lv_cy = heart_cy - 8
    lv_mask = ((X - lv_cx)**2 / (lv_radius_px * z_factor)**2 + 
               (Y - lv_cy)**2 / (lv_radius_px * 1.15 * z_factor)**2) <= 1
    
    # LV myocardium (outer ring)
    lv_wall_thickness = 12  # pixels
    lv_outer = ((X - lv_cx)**2 / ((lv_radius_px + lv_wall_thickness) * z_factor)**2 + 
                (Y - lv_cy)**2 / ((lv_radius_px * 1.15 + lv_wall_thickness) * z_factor)**2) <= 1
    lv_wall = lv_outer & ~lv_mask
    
    # Right ventricle (anterior, crescent-shaped approximated as ellipse)
    rv_cx = heart_cx + 28
    rv_cy = heart_cy - 22
    rv_mask = ((X - rv_cx)**2 / (rv_radius_px * z_factor)**2 + 
               (Y - rv_cy)**2 / (rv_radius_px * 0.75 * z_factor)**2) <= 1
    
    # RV wall (thinner than LV)
    rv_wall_thickness = 5
    rv_outer = ((X - rv_cx)**2 / ((rv_radius_px + rv_wall_thickness) * z_factor)**2 + 
                (Y - rv_cy)**2 / ((rv_radius_px * 0.75 + rv_wall_thickness) * z_factor)**2) <= 1
    rv_wall = rv_outer & ~rv_mask
    
    # Interventricular septum
    sept_cx = heart_cx + 8
    septum_width = 15
    septum = (np.abs(X - sept_cx) <= septum_width/2) & (np.abs(Y - heart_cy) <= 35 * z_factor)
    
    # Outer heart boundary (pericardium region)
    heart_outer = ((X - heart_cx)**2 + (Y - heart_cy)**2) <= (85 * z_factor)**2
    
    # Apply to CT volume
    # Myocardium (~50-60 HU)
    ct[:, :, z][heart_outer & body_mask] = np.random.normal(50, 12, np.sum(heart_outer & body_mask)).astype(np.int16)
    ct[:, :, z][lv_wall & body_mask] = np.random.normal(55, 10, np.sum(lv_wall & body_mask)).astype(np.int16)
    ct[:, :, z][rv_wall & body_mask] = np.random.normal(52, 10, np.sum(rv_wall & body_mask)).astype(np.int16)
    ct[:, :, z][septum & heart_outer & body_mask] = np.random.normal(58, 10, np.sum(septum & heart_outer & body_mask)).astype(np.int16)
    
    # Blood in chambers (~40-50 HU without contrast)
    ct[:, :, z][lv_mask] = np.random.normal(42, 8, np.sum(lv_mask)).astype(np.int16)
    ct[:, :, z][rv_mask] = np.random.normal(38, 8, np.sum(rv_mask)).astype(np.int16)

# === Aorta (descending) ===
aorta_cx, aorta_cy = heart_cx + 15, heart_cy + 35
for z in range(35, 115):
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= 14**2
    ct[:, :, z][aorta_mask] = np.random.normal(48, 8, np.sum(aorta_mask)).astype(np.int16)

# === Save CT volume ===
ct_nii = nib.Nifti1Image(ct, affine)
ct_path = os.path.join(cardiac_dir, "chest_ct.nii.gz")
nib.save(ct_nii, ct_path)
print(f"Chest CT saved: {ct_path}")
print(f"Shape: {ct.shape}, Spacing: {spacing}")

# === Calculate ground truth classification ===
if rv_ratio < 0.9:
    classification = "Normal"
elif rv_ratio <= 1.0:
    classification = "Borderline"
else:
    classification = "RV Dilation"

# === Save ground truth (hidden from agent) ===
gt = {
    "rv_diameter_mm": round(float(rv_diam_mm), 1),
    "lv_diameter_mm": round(float(lv_diam_mm), 1),
    "rv_lv_ratio": round(float(rv_ratio), 3),
    "classification": classification,
    "scenario": scenario,
    "optimal_slice": int(optimal_slice),
    "rv_center_px": [int(rv_cx_actual), int(rv_cy_actual)],
    "lv_center_px": [int(lv_cx_actual), int(lv_cy_actual)],
    "heart_center_px": [int(heart_cx), int(heart_cy)],
    "spacing_mm": list(spacing),
    "volume_shape": list(ct.shape)
}

gt_path = os.path.join(gt_dir, "cardiac_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt, f, indent=2)

# Set restrictive permissions on ground truth
os.chmod(gt_path, 0o600)
os.chmod(gt_dir, 0o700)

print(f"\nGround truth saved: {gt_path}")
print(f"Scenario: {scenario}")
print(f"RV: {rv_diam_mm:.1f}mm, LV: {lv_diam_mm:.1f}mm")
print(f"RV/LV Ratio: {rv_ratio:.3f}")
print(f"Classification: {classification}")
print(f"Optimal slice: {optimal_slice}")
PYEOF

# Verify data was created
CT_FILE="$CARDIAC_DIR/chest_ct.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: Failed to create chest CT volume"
    exit 1
fi
echo "CT volume created successfully"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/cardiac_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer Python script to load CT with appropriate window/level
cat > /tmp/load_cardiac_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/Cardiac/chest_ct.nii.gz"

print("Loading chest CT for cardiac assessment...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set mediastinal window for cardiac visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Mediastinal window: W=400, L=40
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate cardiac level
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Set Red (axial) view to mid-heart level
    redWidget = slicer.app.layoutManager().sliceWidget("Red")
    redLogic = redWidget.sliceLogic()
    redNode = redLogic.GetSliceNode()
    # Approximately slice 72 * 3mm spacing = 216mm from origin
    mid_z = (bounds[4] + bounds[5]) / 2
    redNode.SetSliceOffset(mid_z)
    
    print(f"CT loaded with mediastinal window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Axial view centered at z={mid_z:.1f}mm")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete - ready for cardiac measurement task")
PYEOF

# Launch Slicer
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_cardiac_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/cardiac_initial.png ga

# Set permissions on cardiac directory
chown -R ga:ga "$CARDIAC_DIR" 2>/dev/null || true
chmod -R 755 "$CARDIAC_DIR" 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Cardiac RV/LV Ratio Assessment"
echo "======================================"
echo ""
echo "A chest CT is loaded. Evaluate for right heart strain."
echo ""
echo "Steps:"
echo "  1. Navigate to the cardiac 4-chamber level (both ventricles visible)"
echo "  2. Measure RV maximum transverse diameter (inner wall to inner wall)"
echo "  3. Measure LV maximum transverse diameter at same level"
echo "  4. Calculate RV/LV ratio"
echo "  5. Classify: Normal (<0.9), Borderline (0.9-1.0), RV Dilation (>1.0)"
echo ""
echo "Save outputs to ~/Documents/SlicerData/Cardiac/:"
echo "  - rv_measurement.mrk.json"
echo "  - lv_measurement.mrk.json"
echo "  - cardiac_report.json"
echo ""