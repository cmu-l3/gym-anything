#!/bin/bash
echo "=== Setting up Pericardial Effusion Quantification Task ==="

source /workspace/scripts/task_utils.sh

CARDIAC_DIR="/home/ga/Documents/SlicerData/Cardiac"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$CARDIAC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f "$CARDIAC_DIR/pericardial_thickness.mrk.json" 2>/dev/null || true
rm -f "$CARDIAC_DIR/pericardial_effusion_seg.nii.gz" 2>/dev/null || true
rm -f "$CARDIAC_DIR/pericardial_report.json" 2>/dev/null || true
rm -f /tmp/pericardial_task_result.json 2>/dev/null || true

# Generate synthetic chest CT with pericardial effusion
echo "Generating chest CT with pericardial effusion..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

cardiac_dir = "/home/ga/Documents/SlicerData/Cardiac"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Volume dimensions and spacing
# Typical chest CT: 512x512x200-400 slices
# Using smaller for speed: 256x256x120
nx, ny, nz = 256, 256, 120
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# ============================================================
# Generate CT volume with realistic HU values
# ============================================================
# Air: -1000 HU
# Lung: -800 to -600 HU
# Fat: -100 to -50 HU
# Soft tissue/muscle: 20-60 HU
# Heart muscle (myocardium): 40-80 HU
# Blood (with contrast): 100-200 HU
# Pericardial fluid: -10 to +30 HU
# Bone: 300-1000 HU

ct_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Fill with air initially
ct_data[:] = -1000

# Create coordinate grids
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# ============================================================
# Create body outline (elliptical thorax)
# ============================================================
for z in range(nz):
    # Thorax slightly varies with z (wider at lower levels)
    z_factor = 1.0 + 0.1 * (z - nz/2) / nz
    body_a = 100 * z_factor  # semi-major axis (L-R)
    body_b = 75 * z_factor   # semi-minor axis (A-P)
    body_mask = ((X - center_x)**2 / body_a**2 + (Y - center_y)**2 / body_b**2) <= 1.0
    
    # Fill body with soft tissue
    ct_data[:, :, z][body_mask] = np.random.normal(40, 10, np.sum(body_mask)).astype(np.int16)

# ============================================================
# Create lung fields (bilateral)
# ============================================================
# Right lung (patient's right = image left)
lung_r_cx, lung_r_cy = center_x - 45, center_y - 5
# Left lung (patient's left = image right)
lung_l_cx, lung_l_cy = center_x + 45, center_y - 5

for z in range(15, nz - 10):
    z_norm = (z - 15) / (nz - 25)
    # Lungs are smaller at apex and base
    lung_scale = 1.0 - 0.5 * (2 * z_norm - 1)**2
    
    lung_a = 40 * lung_scale
    lung_b = 50 * lung_scale
    
    # Right lung
    lung_r_mask = ((X - lung_r_cx)**2 / lung_a**2 + (Y - lung_r_cy)**2 / lung_b**2) <= 1.0
    ct_data[:, :, z][lung_r_mask] = np.random.normal(-750, 50, np.sum(lung_r_mask)).astype(np.int16)
    
    # Left lung
    lung_l_mask = ((X - lung_l_cx)**2 / lung_a**2 + (Y - lung_l_cy)**2 / lung_b**2) <= 1.0
    ct_data[:, :, z][lung_l_mask] = np.random.normal(-750, 50, np.sum(lung_l_mask)).astype(np.int16)

# ============================================================
# Create heart (including pericardium and effusion)
# ============================================================
# Heart center (slightly left of midline, in mid-chest)
heart_cx, heart_cy = center_x + 10, center_y + 5

# Heart dimensions (ellipsoid)
heart_a = 45  # L-R
heart_b = 40  # A-P
heart_c_start = 35  # Start slice
heart_c_end = 90    # End slice
heart_c_center = (heart_c_start + heart_c_end) / 2
heart_c = (heart_c_end - heart_c_start) / 2

# Pericardial effusion parameters
# Effusion is between pericardium (outer) and epicardium (on heart surface)
# Make it NON-UNIFORM - thicker posteriorly (dependent)
# Maximum thickness: ~18mm (moderate effusion)
max_effusion_thickness_voxels = 18 / spacing[0]  # ~23 voxels

# Ground truth values
gt_max_thickness_mm = 18.0  # Target maximum thickness
gt_max_location = "posterior"  # Where the maximum is
gt_volume_target_ml = 285  # Target volume in mL

# Create heart and pericardial effusion
effusion_mask = np.zeros((nx, ny, nz), dtype=np.uint8)

for z in range(heart_c_start, heart_c_end):
    # Normalized z position within heart
    z_norm = (z - heart_c_center) / heart_c
    heart_z_scale = np.sqrt(max(0, 1 - z_norm**2))
    
    # Heart radii at this z level
    ha = heart_a * heart_z_scale
    hb = heart_b * heart_z_scale
    
    if ha < 5 or hb < 5:
        continue
    
    # Create heart mask (myocardium + chambers)
    heart_mask = ((X - heart_cx)**2 / ha**2 + (Y - heart_cy)**2 / hb**2) <= 1.0
    
    # Fill heart with myocardium density
    ct_data[:, :, z][heart_mask] = np.random.normal(55, 10, np.sum(heart_mask)).astype(np.int16)
    
    # Create pericardial effusion (non-uniform thickness)
    # Thicker posteriorly (higher Y = posterior in this orientation)
    for i in range(nx):
        for j in range(ny):
            if not heart_mask[i, j]:
                continue
                
            # Distance from heart center
            dx = (i - heart_cx) / ha if ha > 0 else 0
            dy = (j - heart_cy) / hb if hb > 0 else 0
            
            # Direction-dependent effusion thickness
            # Posterior (higher y) gets more fluid (dependent position)
            # dy > 0 means posterior
            direction_factor = 1.0 + 0.8 * max(0, dy)  # 1.0 to 1.8x
            
            # Also slight variation by z (more at dependent base)
            z_dep_factor = 1.0 + 0.2 * (z - heart_c_center) / heart_c if z > heart_c_center else 1.0
            
            local_thickness = max_effusion_thickness_voxels * direction_factor * z_dep_factor * 0.6
            
            # Create pericardial space around heart
            # Outer boundary of effusion
            eff_a = ha + local_thickness
            eff_b = hb + local_thickness
            
            # Check if this point is in the pericardial space (outside heart, inside outer pericardium)
            dist_heart = np.sqrt(dx**2 + dy**2)
            dist_outer = np.sqrt((i - heart_cx)**2 / eff_a**2 + (j - heart_cy)**2 / eff_b**2)
            
            if dist_heart >= 0.85 and dist_outer <= 1.0:
                # This is in the pericardial effusion space
                ct_data[i, j, z] = np.random.randint(-5, 25)  # Fluid density
                effusion_mask[i, j, z] = 1

# ============================================================
# Add spine (posterior structure)
# ============================================================
spine_cx, spine_cy = center_x, center_y + 60
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask] = np.random.normal(500, 100, np.sum(spine_mask)).astype(np.int16)

# ============================================================
# Add ribs (lateral structures)
# ============================================================
for z in range(20, nz - 15, 12):  # Every ~30mm
    for side in [-1, 1]:  # Left and right
        rib_cx = center_x + side * 70
        rib_cy = center_y + 20
        for dz in range(-2, 3):
            if 0 <= z + dz < nz:
                rib_mask = ((X - rib_cx)**2 / 8**2 + (Y - rib_cy)**2 / 25**2) <= 1.0
                ct_data[:, :, z + dz][rib_mask] = np.random.normal(400, 80, np.sum(rib_mask)).astype(np.int16)

# ============================================================
# Calculate ground truth measurements
# ============================================================
voxel_volume_mm3 = float(np.prod(spacing))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

# Calculate actual effusion volume
effusion_volume_voxels = np.sum(effusion_mask)
effusion_volume_ml = effusion_volume_voxels * voxel_volume_ml

# Find maximum thickness (search through slices)
max_thickness_mm = 0
max_thickness_slice = 0
max_thickness_location = "posterior"
max_thickness_coords = [0, 0, 0]

for z in range(heart_c_start, heart_c_end):
    slice_mask = effusion_mask[:, :, z]
    if not np.any(slice_mask):
        continue
    
    # Find thickness at different angles around the heart
    angles = np.linspace(0, 2*np.pi, 36)
    for angle in angles:
        # Ray from heart center outward
        dx = np.cos(angle)
        dy = np.sin(angle)
        
        # Find inner and outer edge along this ray
        inner_dist = None
        outer_dist = None
        
        for r in range(5, 80):
            px = int(heart_cx + r * dx)
            py = int(heart_cy + r * dy)
            
            if 0 <= px < nx and 0 <= py < ny:
                if slice_mask[px, py]:
                    if inner_dist is None:
                        inner_dist = r
                    outer_dist = r
        
        if inner_dist is not None and outer_dist is not None:
            thickness_voxels = outer_dist - inner_dist
            thickness_mm = thickness_voxels * spacing[0]
            
            if thickness_mm > max_thickness_mm:
                max_thickness_mm = thickness_mm
                max_thickness_slice = z
                
                # Determine location based on angle
                if np.pi/4 <= angle <= 3*np.pi/4:
                    max_thickness_location = "posterior"
                elif 3*np.pi/4 < angle <= 5*np.pi/4:
                    max_thickness_location = "lateral_right"
                elif 5*np.pi/4 < angle <= 7*np.pi/4:
                    max_thickness_location = "anterior"
                else:
                    max_thickness_location = "lateral_left"
                
                max_thickness_coords = [
                    float(heart_cx + (inner_dist + outer_dist)/2 * dx) * spacing[0],
                    float(heart_cy + (inner_dist + outer_dist)/2 * dy) * spacing[1],
                    float(z) * spacing[2]
                ]

# Determine severity classification
if max_thickness_mm < 10 or effusion_volume_ml < 100:
    severity = "Small"
elif max_thickness_mm <= 20 or effusion_volume_ml <= 500:
    severity = "Moderate"
else:
    severity = "Large"

# Distribution pattern (circumferential since we created it that way)
distribution = "circumferential"

# ============================================================
# Save CT volume
# ============================================================
ct_path = os.path.join(cardiac_dir, "chest_ct_pericardial.nii.gz")
ct_img = nib.Nifti1Image(ct_data, affine)
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path}")
print(f"  Shape: {ct_data.shape}")
print(f"  Spacing: {spacing} mm")

# ============================================================
# Save ground truth segmentation (hidden from agent)
# ============================================================
gt_seg_path = os.path.join(gt_dir, "pericardial_effusion_gt_seg.nii.gz")
gt_seg_img = nib.Nifti1Image(effusion_mask.astype(np.int16), affine)
nib.save(gt_seg_img, gt_seg_path)
print(f"Ground truth segmentation saved: {gt_seg_path}")

# ============================================================
# Save ground truth measurements (hidden from agent)
# ============================================================
gt_measurements = {
    "max_thickness_mm": float(max_thickness_mm),
    "max_thickness_location": max_thickness_location,
    "max_thickness_slice": int(max_thickness_slice),
    "max_thickness_coords_mm": max_thickness_coords,
    "effusion_volume_ml": float(effusion_volume_ml),
    "effusion_volume_voxels": int(effusion_volume_voxels),
    "severity_classification": severity,
    "distribution_pattern": distribution,
    "voxel_spacing_mm": list(spacing),
    "voxel_volume_ml": float(voxel_volume_ml),
    "heart_center_voxels": [int(heart_cx), int(heart_cy), int((heart_c_start + heart_c_end)/2)],
    "heart_slice_range": [int(heart_c_start), int(heart_c_end)]
}

gt_json_path = os.path.join(gt_dir, "pericardial_effusion_gt.json")
with open(gt_json_path, "w") as f:
    json.dump(gt_measurements, f, indent=2)

print(f"\nGround truth measurements:")
print(f"  Max thickness: {max_thickness_mm:.1f} mm ({max_thickness_location})")
print(f"  Effusion volume: {effusion_volume_ml:.1f} mL")
print(f"  Severity: {severity}")
print(f"  Distribution: {distribution}")

# Save a marker file for the case ID
with open("/tmp/pericardial_case_id", "w") as f:
    f.write("pericardial_001")

print("\nData generation complete!")
PYEOF

# Verify data was created
CT_FILE="$CARDIAC_DIR/chest_ct_pericardial.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume was not created!"
    exit 1
fi
echo "CT volume verified: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/pericardial_effusion_gt.json" ]; then
    echo "ERROR: Ground truth not created!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Set permissions
chown -R ga:ga "$CARDIAC_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Create Slicer Python script to load the CT with cardiac window
cat > /tmp/load_pericardial_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/Cardiac/chest_ct_pericardial.nii.gz"

print("Loading chest CT for pericardial assessment...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT_Pericardial")
    
    # Set cardiac/mediastinal window (good for seeing pericardial fluid)
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
    
    # Center on the heart region (approximate)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center slightly above midpoint (heart level)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        # Offset to heart region
        heart_z = center[2] + 20  # Slightly superior
        if color == "Red":
            sliceNode.SetSliceOffset(heart_z)
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with mediastinal window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for pericardial effusion assessment")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_pericardial_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/pericardial_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Pericardial Effusion Quantification"
echo "==========================================="
echo ""
echo "You are given a chest CT scan of a patient with suspected"
echo "pericardial effusion (fluid around the heart)."
echo ""
echo "Your goal:"
echo "  1. Locate the pericardial effusion (fluid around heart)"
echo "  2. Find the level with MAXIMUM pericardial fluid thickness"
echo "  3. Measure the maximum thickness (mm) using a ruler tool"
echo "  4. Document the location (anterior/posterior/lateral)"
echo "  5. Segment the effusion and calculate volume (mL)"
echo "  6. Classify severity: Small/Moderate/Large"
echo ""
echo "Severity classification:"
echo "  - Small: <10mm thickness OR <100mL"
echo "  - Moderate: 10-20mm thickness OR 100-500mL"
echo "  - Large: >20mm thickness OR >500mL"
echo ""
echo "Pericardial fluid appears as low-density (-10 to +30 HU)"
echo "surrounding the heart muscle (~50-80 HU)."
echo ""
echo "Save your outputs to ~/Documents/SlicerData/Cardiac/"
echo ""