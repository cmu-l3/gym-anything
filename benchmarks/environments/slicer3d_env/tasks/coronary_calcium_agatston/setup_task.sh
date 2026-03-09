#!/bin/bash
echo "=== Setting up Coronary Calcium Agatston Score Task ==="

source /workspace/scripts/task_utils.sh

CARDIAC_DIR="/home/ga/Documents/SlicerData/Cardiac"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="cardiac_cac_001"

# Create directories
mkdir -p "$CARDIAC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Check if cardiac data already exists
if [ -f "$CARDIAC_DIR/${CASE_ID}.nii.gz" ] && [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_calcium_gt.json" ]; then
    echo "Cardiac CT data already exists"
else
    echo "Generating cardiac CT data with coronary calcium deposits..."
    
    # Generate synthetic cardiac CT with known calcium deposits
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

from scipy.ndimage import label as scipy_label

case_id = "cardiac_cac_001"
cardiac_dir = "/home/ga/Documents/SlicerData/Cardiac"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Cardiac CT parameters (standard calcium scoring protocol)
# Typical: 512x512x100-200, 0.5mm x 0.5mm x 2.5-3.0mm spacing
nx, ny, nz = 256, 256, 80
spacing = (0.68, 0.68, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# ============================================================
# Generate CT volume with realistic HU values
# ============================================================
ct_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Fill with soft tissue background (with noise)
ct_data[:] = np.random.normal(40, 12, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical chest)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Chest cavity (elliptical)
body_mask = ((X - center_x)**2 / (110**2) + (Y - center_y)**2 / (90**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create lungs (dark regions)
lung_left_cx = center_x - 50
lung_right_cx = center_x + 50
lung_cy = center_y - 10

for z in range(10, 70):
    # Left lung
    left_lung = ((X - lung_left_cx)**2 / (35**2) + (Y - lung_cy)**2 / (45**2)) <= 1.0
    ct_data[:, :, z][left_lung & body_mask] = np.random.normal(-800, 50, (np.sum(left_lung & body_mask),)).astype(np.int16)
    
    # Right lung
    right_lung = ((X - lung_right_cx)**2 / (40**2) + (Y - lung_cy)**2 / (45**2)) <= 1.0
    ct_data[:, :, z][right_lung & body_mask] = np.random.normal(-800, 50, (np.sum(right_lung & body_mask),)).astype(np.int16)

# Create spine (bright bone posterior)
spine_cx, spine_cy = center_x, center_y + 65
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask] = np.random.normal(450, 60, (np.sum(spine_mask),)).astype(np.int16)

# Create sternum (anterior)
sternum_cx, sternum_cy = center_x, center_y - 75
for z in range(15, 65):
    sternum_mask = ((X - sternum_cx)**2 / (8**2) + (Y - sternum_cy)**2 / (4**2)) <= 1.0
    ct_data[:, :, z][sternum_mask & body_mask] = np.random.normal(400, 50, (np.sum(sternum_mask & body_mask),)).astype(np.int16)

# Create heart (mediastinum - soft tissue density)
heart_cx, heart_cy = center_x - 5, center_y + 5
heart_slices = range(20, 60)

for z in heart_slices:
    # Elliptical heart shape
    z_factor = 1.0 - 0.3 * abs(z - 40) / 20  # Taper at ends
    heart_rx = 45 * z_factor
    heart_ry = 55 * z_factor
    heart_mask = ((X - heart_cx)**2 / (heart_rx**2) + (Y - heart_cy)**2 / (heart_ry**2)) <= 1.0
    # Cardiac muscle density
    ct_data[:, :, z][heart_mask & body_mask] = np.random.normal(45, 10, (np.sum(heart_mask & body_mask),)).astype(np.int16)

# Create aorta (ascending and descending)
aorta_asc_cx, aorta_asc_cy = center_x + 15, center_y - 5
aorta_desc_cx, aorta_desc_cy = center_x - 25, center_y + 40

for z in range(25, 70):
    # Ascending aorta (with contrast ~150 HU)
    aorta_asc_mask = ((X - aorta_asc_cx)**2 + (Y - aorta_asc_cy)**2) <= 15**2
    ct_data[:, :, z][aorta_asc_mask & body_mask] = np.random.normal(150, 20, (np.sum(aorta_asc_mask & body_mask),)).astype(np.int16)
    
    # Descending aorta
    aorta_desc_mask = ((X - aorta_desc_cx)**2 + (Y - aorta_desc_cy)**2) <= 12**2
    ct_data[:, :, z][aorta_desc_mask & body_mask] = np.random.normal(150, 20, (np.sum(aorta_desc_mask & body_mask),)).astype(np.int16)

# ============================================================
# Add coronary artery calcium deposits
# ============================================================
# Create known calcium deposits with specific properties
calcium_deposits = []
calcium_mask = np.zeros((nx, ny, nz), dtype=np.int16)

# Coronary artery approximate locations (simplified)
# LAD: runs anteriorly in interventricular groove
# LCx: runs in left atrioventricular groove
# RCA: runs in right atrioventricular groove
# LM: short segment before bifurcation

coronary_arteries = {
    "LM": {"center": (center_x + 25, center_y - 15), "z_range": (35, 40), "vessel_radius": 3},
    "LAD": {"center": (center_x + 10, center_y - 30), "z_range": (30, 50), "vessel_radius": 2.5},
    "LCx": {"center": (center_x + 35, center_y + 10), "z_range": (32, 48), "vessel_radius": 2},
    "RCA": {"center": (center_x - 30, center_y - 25), "z_range": (30, 55), "vessel_radius": 2.5},
}

# Add calcium deposits to each vessel
total_agatston = 0
per_vessel_scores = {"LM": 0, "LAD": 0, "LCx": 0, "RCA": 0}
lesion_id = 0

# Patient profile: Moderate calcium burden (score ~150-300)
calcium_configs = [
    # LAD deposits (usually most affected)
    {"vessel": "LAD", "offset": (2, -5), "z": 35, "size": (4, 3, 2), "peak_hu": 350},
    {"vessel": "LAD", "offset": (-3, 2), "z": 42, "size": (5, 4, 2), "peak_hu": 280},
    {"vessel": "LAD", "offset": (1, -2), "z": 48, "size": (3, 3, 1), "peak_hu": 420},
    
    # LCx deposits
    {"vessel": "LCx", "offset": (3, 2), "z": 38, "size": (4, 3, 2), "peak_hu": 220},
    {"vessel": "LCx", "offset": (-2, -1), "z": 45, "size": (3, 2, 1), "peak_hu": 180},
    
    # RCA deposits
    {"vessel": "RCA", "offset": (2, 3), "z": 40, "size": (5, 4, 2), "peak_hu": 310},
    {"vessel": "RCA", "offset": (-1, -2), "z": 50, "size": (3, 3, 1), "peak_hu": 250},
    
    # LM deposit (less common but clinically significant)
    {"vessel": "LM", "offset": (1, 1), "z": 37, "size": (3, 2, 1), "peak_hu": 190},
]

for config in calcium_configs:
    vessel = config["vessel"]
    base_cx, base_cy = coronary_arteries[vessel]["center"]
    offset_x, offset_y = config["offset"]
    z_center = config["z"]
    size_x, size_y, size_z = config["size"]
    peak_hu = config["peak_hu"]
    
    # Create ellipsoidal calcium deposit
    lesion_voxels = 0
    lesion_area_mm2_list = []
    max_hu_in_lesion = 0
    
    for dz in range(-size_z, size_z + 1):
        z = z_center + dz
        if z < 0 or z >= nz:
            continue
            
        slice_area = 0
        for dx in range(-size_x, size_x + 1):
            for dy in range(-size_y, size_y + 1):
                # Check if within ellipsoid
                if (dx/size_x)**2 + (dy/size_y)**2 + (dz/max(size_z, 1))**2 <= 1.0:
                    x = base_cx + offset_x + dx
                    y = base_cy + offset_y + dy
                    if 0 <= x < nx and 0 <= y < ny:
                        # Assign HU value (with some variation)
                        hu_value = peak_hu + np.random.randint(-30, 30)
                        hu_value = max(130, min(600, hu_value))  # Clamp to realistic range
                        ct_data[x, y, z] = hu_value
                        calcium_mask[x, y, z] = lesion_id + 1
                        lesion_voxels += 1
                        slice_area += spacing[0] * spacing[1]
                        max_hu_in_lesion = max(max_hu_in_lesion, hu_value)
        
        if slice_area >= 1.0:  # Minimum 1 mm² per slice
            lesion_area_mm2_list.append(slice_area)
    
    # Calculate Agatston score for this lesion
    if lesion_area_mm2_list:
        # Density factor based on peak HU
        if max_hu_in_lesion >= 400:
            density_factor = 4
        elif max_hu_in_lesion >= 300:
            density_factor = 3
        elif max_hu_in_lesion >= 200:
            density_factor = 2
        else:
            density_factor = 1
        
        # Agatston score = sum of (area per slice × density factor)
        lesion_score = sum(lesion_area_mm2_list) * density_factor
        total_agatston += lesion_score
        per_vessel_scores[vessel] += lesion_score
        
        calcium_deposits.append({
            "lesion_id": lesion_id,
            "vessel": vessel,
            "center_voxel": [base_cx + offset_x, base_cy + offset_y, z_center],
            "center_mm": [
                float((base_cx + offset_x) * spacing[0]),
                float((base_cy + offset_y) * spacing[1]),
                float(z_center * spacing[2])
            ],
            "peak_hu": int(max_hu_in_lesion),
            "density_factor": density_factor,
            "total_area_mm2": float(sum(lesion_area_mm2_list)),
            "lesion_score": float(lesion_score),
            "voxel_count": lesion_voxels
        })
        
        lesion_id += 1

# Determine risk category
if total_agatston == 0:
    risk_category = "No identifiable disease"
elif total_agatston <= 10:
    risk_category = "Minimal plaque burden"
elif total_agatston <= 100:
    risk_category = "Mild plaque burden"
elif total_agatston <= 400:
    risk_category = "Moderate plaque burden"
else:
    risk_category = "Severe plaque burden"

# ============================================================
# Save CT volume
# ============================================================
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(cardiac_dir, f"{case_id}.nii.gz")
nib.save(ct_nii, ct_path)
print(f"CT volume saved: {ct_path}")
print(f"  Shape: {ct_data.shape}")
print(f"  Spacing: {spacing} mm")

# Save calcium mask (for verification)
calcium_nii = nib.Nifti1Image(calcium_mask, affine)
calcium_path = os.path.join(gt_dir, f"{case_id}_calcium_mask.nii.gz")
nib.save(calcium_nii, calcium_path)
print(f"Calcium mask saved: {calcium_path}")

# ============================================================
# Save ground truth
# ============================================================
gt_data = {
    "case_id": case_id,
    "total_agatston_score": float(round(total_agatston, 1)),
    "per_vessel_scores": {k: float(round(v, 1)) for k, v in per_vessel_scores.items()},
    "risk_category": risk_category,
    "lesion_count": len(calcium_deposits),
    "lesions": calcium_deposits,
    "volume_info": {
        "shape": list(ct_data.shape),
        "spacing_mm": list(spacing),
        "voxel_volume_mm3": float(np.prod(spacing))
    },
    "scoring_method": "Agatston (area × density factor)",
    "density_factors": {
        "130-199": 1,
        "200-299": 2,
        "300-399": 3,
        "400+": 4
    }
}

gt_path = os.path.join(gt_dir, f"{case_id}_calcium_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved: {gt_path}")
print(f"\n=== Ground Truth Summary ===")
print(f"Total Agatston Score: {total_agatston:.1f}")
print(f"Risk Category: {risk_category}")
print(f"Per-vessel scores:")
for vessel, score in per_vessel_scores.items():
    print(f"  {vessel}: {score:.1f}")
print(f"Number of lesions: {len(calcium_deposits)}")
PYEOF

fi

# Get case ID
CT_FILE="$CARDIAC_DIR/${CASE_ID}.nii.gz"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_calcium_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state - clean up any previous outputs
rm -f /tmp/calcium_task_result.json 2>/dev/null || true
rm -f "$CARDIAC_DIR/calcium_segmentation.nii.gz" 2>/dev/null || true
rm -f "$CARDIAC_DIR/agatston_report.json" 2>/dev/null || true

# Create Slicer Python script to load CT with cardiac window
cat > /tmp/load_cardiac_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading Cardiac CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("CardiacCT")
    
    # Set cardiac/mediastinal window (good for seeing calcium)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Wide window to see both soft tissue and calcium
        displayNode.SetWindow(1500)
        displayNode.SetLevel(200)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on cardiac region (approximately mid-volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        # Offset to cardiac region (slightly anterior and caudal)
        if color == "Red":
            sliceNode.SetSliceOffset(center[2] * 0.5)  # Cardiac level
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with cardiac window (W=1500, L=200)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("")
    print("TIP: Calcium appears bright (HU >= 130)")
    print("Look for bright spots in the coronary artery distribution")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for calcium scoring task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT data
echo "Launching 3D Slicer with cardiac CT..."
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
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/calcium_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Coronary Artery Calcium Agatston Score"
echo "=============================================="
echo ""
echo "You have a non-contrast chest CT. Calculate the Agatston calcium score."
echo ""
echo "Steps:"
echo "  1. Navigate to cardiac region (mid-thorax)"
echo "  2. Identify coronary calcium (bright spots, HU >= 130)"
echo "  3. Segment all calcium deposits"
echo "  4. Calculate Agatston score:"
echo "     Score = Area(mm²) × Density Factor"
echo "     Factors: 130-199→1, 200-299→2, 300-399→3, >=400→4"
echo "  5. Attribute calcium to vessels (LM, LAD, LCx, RCA)"
echo "  6. Classify risk:"
echo "     0: None | 1-10: Minimal | 11-100: Mild"
echo "     101-400: Moderate | >400: Severe"
echo ""
echo "Save outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/Cardiac/calcium_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/Cardiac/agatston_report.json"
echo ""