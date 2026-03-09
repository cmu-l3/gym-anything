#!/bin/bash
echo "=== Setting up Gallbladder Cholecystitis Screening Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_gb_0001"

mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Record initial state - remove any existing outputs
rm -f "$AMOS_DIR/gallbladder_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/gallbladder_report.json" 2>/dev/null || true
rm -f /tmp/gallbladder_task_result.json 2>/dev/null || true

# Check if gallbladder data already exists
if [ -f "$AMOS_DIR/${CASE_ID}.nii.gz" ] && [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_gb_gt.json" ]; then
    echo "Gallbladder CT data already exists for $CASE_ID"
else
    echo "Generating abdominal CT with gallbladder..."
    
    # Generate synthetic abdominal CT with gallbladder
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

case_id = "amos_gb_0001"
amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# CT volume dimensions
nx, ny, nz = 256, 256, 120
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

print(f"Creating CT volume: {nx}x{ny}x{nz}, spacing: {spacing}")

# Initialize CT with soft tissue background
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (85**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (vertebral body)
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 18**2
    ct_data[:, :, z][spine_mask] = np.random.normal(450, 60, (np.sum(spine_mask),)).astype(np.int16)

# Create liver (right side, label 6)
# Large structure in RUQ
liver_cx, liver_cy = center_x - 35, center_y - 15
liver_mask_3d = np.zeros((nx, ny, nz), dtype=bool)

for z in range(25, 95):
    z_factor = 1.0 - abs(z - 60) / 60.0
    r_x = 55 * z_factor
    r_y = 45 * z_factor
    if r_x > 5 and r_y > 5:
        liver_slice = ((X - liver_cx)**2 / (r_x**2) + (Y - liver_cy)**2 / (r_y**2)) <= 1.0
        liver_mask_3d[:, :, z] = liver_slice & body_mask
        ct_data[:, :, z][liver_slice & body_mask] = np.random.normal(55, 12, (np.sum(liver_slice & body_mask),)).astype(np.int16)

# ============================================================
# Create Gallbladder (the main structure for this task)
# Located along inferior margin of liver, right side
# ============================================================

# Gallbladder parameters - make it slightly abnormal for clinical interest
# Case: Mildly distended with borderline wall thickening
gb_length_cm = 9.2  # Slightly enlarged (normal <10)
gb_transverse_cm = 4.2  # Mildly distended (normal <5)
gb_wall_mm = 3.8  # Borderline thickened (normal ≤3)

# Convert to voxels
gb_length_vox = gb_length_cm * 10 / spacing[2]  # Along z-axis
gb_transverse_vox = gb_transverse_cm * 10 / spacing[0]
gb_wall_vox = gb_wall_mm / spacing[0]

# Gallbladder center position (in liver fossa)
gb_cx = center_x - 65  # Right side
gb_cy = center_y - 35  # Anterior
gb_z_start = 40
gb_z_end = int(gb_z_start + gb_length_vox)

print(f"Gallbladder: length={gb_length_cm}cm, transverse={gb_transverse_cm}cm, wall={gb_wall_mm}mm")
print(f"Gallbladder z range: {gb_z_start} to {gb_z_end}")

# Create gallbladder mask (pear-shaped)
gb_mask = np.zeros((nx, ny, nz), dtype=bool)
gb_wall_mask = np.zeros((nx, ny, nz), dtype=bool)
gb_lumen_mask = np.zeros((nx, ny, nz), dtype=bool)

for z in range(gb_z_start, min(gb_z_end, nz)):
    # Pear shape: wider at fundus (lower z), narrower at neck (higher z)
    z_frac = (z - gb_z_start) / max(1, (gb_z_end - gb_z_start))
    
    # Taper from fundus (wider) to neck (narrower)
    taper = 1.0 - 0.5 * z_frac  # 1.0 at fundus, 0.5 at neck
    
    r_outer = (gb_transverse_vox / 2) * taper
    r_inner = r_outer - gb_wall_vox
    
    if r_outer < 2:
        continue
    
    # Outer boundary (wall + lumen)
    outer_mask = ((X - gb_cx)**2 + (Y - gb_cy)**2) <= r_outer**2
    
    # Inner boundary (lumen only)
    if r_inner > 0:
        inner_mask = ((X - gb_cx)**2 + (Y - gb_cy)**2) <= r_inner**2
    else:
        inner_mask = np.zeros_like(outer_mask)
    
    # Wall is outer minus inner
    wall_slice = outer_mask & ~inner_mask & body_mask
    lumen_slice = inner_mask & body_mask
    
    gb_mask[:, :, z] = outer_mask & body_mask
    gb_wall_mask[:, :, z] = wall_slice
    gb_lumen_mask[:, :, z] = lumen_slice
    
    # Set CT values
    # Wall: soft tissue with enhancement (~80-100 HU)
    ct_data[:, :, z][wall_slice] = np.random.normal(90, 15, (np.sum(wall_slice),)).astype(np.int16)
    # Lumen: fluid (~0-20 HU, bile)
    ct_data[:, :, z][lumen_slice] = np.random.normal(10, 8, (np.sum(lumen_slice),)).astype(np.int16)

# Add slight pericholecystic fat stranding (subtle finding)
fat_stranding_region = np.zeros((nx, ny, nz), dtype=bool)
for z in range(gb_z_start, min(gb_z_end, nz)):
    z_frac = (z - gb_z_start) / max(1, (gb_z_end - gb_z_start))
    taper = 1.0 - 0.5 * z_frac
    r_fat = (gb_transverse_vox / 2 + 5) * taper
    r_outer = (gb_transverse_vox / 2) * taper
    
    fat_ring = (((X - gb_cx)**2 + (Y - gb_cy)**2) <= r_fat**2) & \
               (((X - gb_cx)**2 + (Y - gb_cy)**2) > r_outer**2) & body_mask
    fat_stranding_region[:, :, z] = fat_ring
    # Slightly increased attenuation in pericholecystic fat (-30 to -10 instead of -80)
    ct_data[:, :, z][fat_ring] = np.random.normal(-20, 15, (np.sum(fat_ring),)).astype(np.int16)

# Add aorta for anatomical reference
aorta_cx, aorta_cy = center_x, center_y + 25
for z in range(nz):
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= 12**2
    ct_data[:, :, z][aorta_mask & body_mask] = np.random.normal(180, 25, (np.sum(aorta_mask & body_mask),)).astype(np.int16)

# Add spleen (left side)
spleen_cx, spleen_cy = center_x + 55, center_y + 5
for z in range(35, 75):
    spleen_mask = ((X - spleen_cx)**2 + (Y - spleen_cy)**2) <= 25**2
    ct_data[:, :, z][spleen_mask & body_mask] = np.random.normal(50, 10, (np.sum(spleen_mask & body_mask),)).astype(np.int16)

# Add subcutaneous fat layer
fat_inner = ((X - center_x)**2 / (92**2) + (Y - center_y)**2 / (77**2)) <= 1.0
fat_outer = ((X - center_x)**2 / (98**2) + (Y - center_y)**2 / (83**2)) <= 1.0
fat_ring = fat_outer & ~fat_inner
for z in range(nz):
    ct_data[:, :, z][fat_ring & body_mask] = np.random.normal(-80, 12, (np.sum(fat_ring & body_mask),)).astype(np.int16)

# ============================================================
# Create label map for ground truth
# ============================================================
label_data = np.zeros((nx, ny, nz), dtype=np.int16)
label_data[liver_mask_3d] = 6  # Liver
label_data[gb_mask] = 9  # Gallbladder (AMOS label)

# ============================================================
# Save NIfTI files
# ============================================================
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path}")

label_img = nib.Nifti1Image(label_data, affine)
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
nib.save(label_img, label_path)
print(f"Label map saved: {label_path}")

# ============================================================
# Compute ground truth measurements
# ============================================================

# Find gallbladder bounding box
gb_coords = np.argwhere(gb_mask)
if len(gb_coords) > 0:
    z_min, z_max = gb_coords[:, 2].min(), gb_coords[:, 2].max()
    
    # Length (craniocaudal extent)
    gt_length_mm = (z_max - z_min + 1) * spacing[2]
    gt_length_cm = gt_length_mm / 10.0
    
    # Find max transverse diameter (at widest slice)
    max_transverse_mm = 0
    max_transverse_slice = 0
    for z in range(int(z_min), int(z_max) + 1):
        slice_mask = gb_mask[:, :, z]
        if np.any(slice_mask):
            rows = np.any(slice_mask, axis=1)
            cols = np.any(slice_mask, axis=0)
            rmin, rmax = np.where(rows)[0][[0, -1]]
            cmin, cmax = np.where(cols)[0][[0, -1]]
            width_mm = (cmax - cmin + 1) * spacing[0]
            height_mm = (rmax - rmin + 1) * spacing[1]
            transverse = max(width_mm, height_mm)
            if transverse > max_transverse_mm:
                max_transverse_mm = transverse
                max_transverse_slice = z
    
    gt_transverse_cm = max_transverse_mm / 10.0
    
    # Wall thickness (from parameters used)
    gt_wall_thickness_mm = gb_wall_mm
    
else:
    gt_length_cm = gb_length_cm
    gt_transverse_cm = gb_transverse_cm
    gt_wall_thickness_mm = gb_wall_mm

# Clinical classification based on measurements
distension = gt_length_cm > 10.0 or gt_transverse_cm > 5.0
wall_thickening = gt_wall_thickness_mm > 3.0
pericholecystic_changes = True  # We added fat stranding

if wall_thickening and distension:
    classification = "Imaging Consistent with Acute Cholecystitis"
elif wall_thickening:
    classification = "Wall Thickening"
elif distension:
    classification = "Distended (Hydrops)"
else:
    classification = "Normal"

# Ground truth JSON
gt_data = {
    "case_id": case_id,
    "measurements": {
        "length_cm": round(gt_length_cm, 2),
        "transverse_diameter_cm": round(gt_transverse_cm, 2),
        "wall_thickness_mm": round(gt_wall_thickness_mm, 2)
    },
    "findings": {
        "distension": distension,
        "wall_thickening": wall_thickening,
        "pericholecystic_fluid": False,
        "pericholecystic_fat_stranding": pericholecystic_changes,
        "gallstones_visible": False
    },
    "classification": classification,
    "gallbladder_location": {
        "center_x_vox": int(gb_cx),
        "center_y_vox": int(gb_cy),
        "z_start_vox": int(gb_z_start),
        "z_end_vox": int(min(gb_z_end, nz-1))
    },
    "volume_dimensions": [nx, ny, nz],
    "spacing_mm": list(spacing)
}

gt_path = os.path.join(gt_dir, f"{case_id}_gb_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"  Length: {gt_length_cm:.2f} cm")
print(f"  Transverse: {gt_transverse_cm:.2f} cm")
print(f"  Wall thickness: {gt_wall_thickness_mm:.2f} mm")
print(f"  Classification: {classification}")
PYEOF
fi

# Save the case ID
echo "$CASE_ID" > /tmp/gallbladder_case_id.txt

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_gb_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Create Slicer Python script to load the CT
cat > /tmp/load_gallbladder_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT_RUQ")
    
    # Set abdominal soft tissue window
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate gallbladder location (RUQ)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Set to mid-abdomen level where gallbladder would be
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        if color == "Red":  # Axial - set to ~middle of volume
            z_center = (bounds[4] + bounds[5]) / 2
            sliceNode.SetSliceOffset(z_center)
        elif color == "Green":  # Coronal
            y_center = (bounds[2] + bounds[3]) / 2 - 20  # Slightly anterior
            sliceNode.SetSliceOffset(y_center)
        else:  # Sagittal
            x_center = (bounds[0] + bounds[1]) / 2 - 40  # Right side
            sliceNode.SetSliceOffset(x_center)
    
    print(f"CT loaded with abdominal window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for gallbladder assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_gallbladder_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/gallbladder_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Gallbladder Morphometry and Cholecystitis Screening"
echo "=========================================================="
echo ""
echo "Clinical scenario: Patient with right upper quadrant pain."
echo ""
echo "Your tasks:"
echo "  1. Locate the gallbladder (RUQ, inferior to liver)"
echo "  2. Measure longitudinal LENGTH (fundus to neck) - normal: 7-10cm"
echo "  3. Measure maximum TRANSVERSE DIAMETER - normal: 3-4cm"
echo "  4. Measure WALL THICKNESS at thickest point - normal: ≤3mm"
echo "  5. Assess for distension, wall thickening, pericholecystic changes"
echo "  6. Classify and create report"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/AMOS/gallbladder_measurements.mrk.json"
echo "  - ~/Documents/SlicerData/AMOS/gallbladder_report.json"
echo ""