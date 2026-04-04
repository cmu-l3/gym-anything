#!/bin/bash
echo "=== Setting up Renal Cyst Bosniak Classification Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare AMOS data first (downloads or generates abdominal CT)
echo "Preparing abdominal CT data..."
/workspace/scripts/prepare_amos_data.sh "$CASE_ID" || true

# Get case ID
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

echo "Using case: $CASE_ID"

# Create synthetic renal cyst with known properties
echo "Creating renal cyst lesion with known characteristics..."
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

try:
    from scipy.ndimage import binary_erosion
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import binary_erosion

amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"
case_id = os.environ.get("CASE_ID", "amos_0001")

# Load the CT volume
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
if not os.path.exists(ct_path):
    print(f"ERROR: CT file not found at {ct_path}")
    sys.exit(1)

ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata().astype(np.float32)
affine = ct_nii.affine
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Load label map if available
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if os.path.exists(label_path):
    labels = nib.load(label_path).get_fdata().astype(np.int16)
else:
    # Create approximate kidney regions
    nx, ny, nz = ct_data.shape
    labels = np.zeros_like(ct_data, dtype=np.int16)
    center_x, center_y = nx // 2, ny // 2
    Y, X = np.ogrid[:nx, :ny]
    for z in range(int(nz * 0.3), int(nz * 0.6)):
        # Right kidney
        rk_cx, rk_cy = center_x - 35, center_y + 30
        rk_mask = ((X - rk_cx)**2 / 20**2 + (Y - rk_cy)**2 / 15**2) <= 1
        labels[:, :, z][rk_mask] = 2
        # Left kidney
        lk_cx, lk_cy = center_x + 35, center_y + 30
        lk_mask = ((X - lk_cx)**2 / 20**2 + (Y - lk_cy)**2 / 15**2) <= 1
        labels[:, :, z][lk_mask] = 3

# Reproducible random configuration
np.random.seed(42)

# Cyst configurations with different Bosniak categories
cyst_configs = [
    {"category": "I", "hu": 8, "wall_mm": 0.5, "septa": False, "calc": False, "diameter_mm": 25},
    {"category": "II", "hu": 12, "wall_mm": 0.8, "septa": True, "calc": False, "diameter_mm": 22},
    {"category": "II", "hu": 85, "wall_mm": 0.5, "septa": False, "calc": False, "diameter_mm": 28},
    {"category": "IIF", "hu": 15, "wall_mm": 1.2, "septa": True, "calc": True, "diameter_mm": 35},
]

config = cyst_configs[np.random.randint(len(cyst_configs))]
print(f"Creating Bosniak Category {config['category']} cyst")

# Select right kidney (label 2)
kidney_label = 2
kidney_name = "right"
pole = "mid"

kidney_mask = (labels == kidney_label)
if not np.any(kidney_mask):
    print("Creating approximate kidney location...")
    nx, ny, nz = ct_data.shape
    kidney_mask = np.zeros_like(ct_data, dtype=bool)
    Y, X = np.ogrid[:nx, :ny]
    for z in range(int(nz * 0.35), int(nz * 0.55)):
        cx, cy = nx // 2 - 35, ny // 2 + 30
        mask_2d = ((X - cx)**2 / 20**2 + (Y - cy)**2 / 15**2) <= 1
        kidney_mask[:, :, z] = mask_2d

# Find kidney center for cyst placement
kidney_coords = np.argwhere(kidney_mask)
if len(kidney_coords) == 0:
    print("ERROR: Could not find kidney region")
    sys.exit(1)

kidney_center = kidney_coords.mean(axis=0).astype(int)
print(f"Kidney center: {kidney_center}")

# Erode kidney to place cyst inside
eroded_kidney = binary_erosion(kidney_mask, iterations=5)
eroded_coords = np.argwhere(eroded_kidney)

if len(eroded_coords) > 0:
    cyst_center_idx = np.random.randint(len(eroded_coords))
    cyst_center = eroded_coords[cyst_center_idx]
else:
    cyst_center = kidney_center

# Calculate cyst radius in voxels
diameter_mm = config["diameter_mm"]
radius_voxels = [diameter_mm / 2 / s for s in spacing]

# Create spherical cyst
cyst_mask = np.zeros_like(ct_data, dtype=bool)
for x in range(max(0, int(cyst_center[0] - radius_voxels[0] - 2)), 
               min(ct_data.shape[0], int(cyst_center[0] + radius_voxels[0] + 2))):
    for y in range(max(0, int(cyst_center[1] - radius_voxels[1] - 2)),
                   min(ct_data.shape[1], int(cyst_center[1] + radius_voxels[1] + 2))):
        for z in range(max(0, int(cyst_center[2] - radius_voxels[2] - 2)),
                       min(ct_data.shape[2], int(cyst_center[2] + radius_voxels[2] + 2))):
            dist = np.sqrt(((x - cyst_center[0]) * spacing[0])**2 +
                          ((y - cyst_center[1]) * spacing[1])**2 +
                          ((z - cyst_center[2]) * spacing[2])**2)
            if dist <= diameter_mm / 2:
                cyst_mask[x, y, z] = True

# Fill cyst with appropriate HU
cyst_hu = config["hu"]
ct_modified = ct_data.copy()

# Interior and wall
cyst_interior = binary_erosion(cyst_mask, iterations=1)
cyst_wall = cyst_mask & ~cyst_interior

# Interior: target HU with small noise
ct_modified[cyst_interior] = np.random.normal(cyst_hu, 3, np.sum(cyst_interior))

# Wall: slightly higher HU
wall_hu = cyst_hu + 20 if config["wall_mm"] > 1 else cyst_hu + 5
ct_modified[cyst_wall] = np.random.normal(wall_hu, 5, np.sum(cyst_wall))

# Add septation if specified
if config["septa"]:
    mid_z = int(cyst_center[2])
    for z in range(max(0, mid_z-1), min(ct_data.shape[2], mid_z+2)):
        septa_slice = cyst_mask[:, :, z] & cyst_interior[:, :, z]
        ct_modified[:, :, z][septa_slice] = np.random.normal(30, 5, np.sum(septa_slice))

# Add calcification if specified
if config["calc"]:
    calc_center = cyst_center + np.array([int(radius_voxels[0]*0.7), 0, 0])
    for dx in range(-2, 3):
        for dy in range(-2, 3):
            for dz in range(-1, 2):
                x = int(calc_center[0] + dx)
                y = int(calc_center[1] + dy)
                z = int(calc_center[2] + dz)
                if 0 <= x < ct_data.shape[0] and 0 <= y < ct_data.shape[1] and 0 <= z < ct_data.shape[2]:
                    if cyst_mask[x, y, z]:
                        ct_modified[x, y, z] = np.random.normal(150, 20)

# Save modified CT
modified_path = os.path.join(amos_dir, f"{case_id}_with_cyst.nii.gz")
modified_nii = nib.Nifti1Image(ct_modified.astype(np.int16), affine, ct_nii.header)
nib.save(modified_nii, modified_path)
print(f"Modified CT saved to: {modified_path}")

# Calculate ground truth measurements
cyst_coords = np.argwhere(cyst_mask)
cyst_min = cyst_coords.min(axis=0)
cyst_max = cyst_coords.max(axis=0)

diameters_voxels = cyst_max - cyst_min + 1
diameters_mm = [float(d * s) for d, s in zip(diameters_voxels, spacing)]
max_diameter_mm = max(diameters_mm[:2])

# Measure actual internal HU
internal_values = ct_modified[cyst_interior]
internal_hu_mean = float(np.mean(internal_values))
internal_hu_std = float(np.std(internal_values))
internal_hu_min = float(np.min(internal_values))
internal_hu_max = float(np.max(internal_values))

# Get reference parenchyma HU
parenchyma_mask = kidney_mask & ~cyst_mask
if np.any(parenchyma_mask):
    parenchyma_hu = float(np.mean(ct_data[parenchyma_mask]))
else:
    parenchyma_hu = 35.0

# Management recommendations
recommendations = {
    "I": "Benign simple cyst. No follow-up required.",
    "II": "Benign minimally complex cyst. No follow-up required.",
    "IIF": "Indeterminate cyst requiring imaging follow-up at 6-12 months.",
    "III": "Indeterminate cyst. Consider surgical excision or biopsy.",
    "IV": "Likely malignant. Recommend surgical excision."
}

# Save ground truth
gt_data = {
    "case_id": case_id,
    "cyst_location": f"{kidney_name} kidney, {pole} pole",
    "cyst_center_voxels": cyst_center.tolist(),
    "cyst_center_mm": [float(c * s) for c, s in zip(cyst_center, spacing)],
    "max_diameter_mm": float(max_diameter_mm),
    "diameters_mm": diameters_mm,
    "internal_hu_mean": internal_hu_mean,
    "internal_hu_std": internal_hu_std,
    "internal_hu_range": [internal_hu_min, internal_hu_max],
    "reference_parenchyma_hu": parenchyma_hu,
    "wall_thickness_mm": config["wall_mm"],
    "has_septations": config["septa"],
    "has_calcification": config["calc"],
    "bosniak_category": config["category"],
    "recommendation": recommendations[config["category"]],
    "cyst_volume_ml": float(np.sum(cyst_mask) * np.prod(spacing) / 1000),
    "voxel_spacing_mm": [float(s) for s in spacing]
}

gt_path = os.path.join(gt_dir, f"{case_id}_cyst_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to: {gt_path}")
print(f"\nCyst characteristics:")
print(f"  Location: {gt_data['cyst_location']}")
print(f"  Max diameter: {max_diameter_mm:.1f} mm")
print(f"  Internal HU: {internal_hu_mean:.1f} +/- {internal_hu_std:.1f}")
print(f"  Bosniak Category: {config['category']}")
PYEOF

# Export case ID and ground truth path for other scripts
echo "$CASE_ID" > /tmp/renal_cyst_case_id

# Ensure output directory exists and is clean
mkdir -p "$AMOS_DIR"
rm -f "$AMOS_DIR/cyst_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/bosniak_report.json" 2>/dev/null || true
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true

# Record initial state
ls -la "$AMOS_DIR"/ > /tmp/initial_amos_state.txt 2>/dev/null || true

# Close any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f Slicer 2>/dev/null || true
sleep 2

# Launch Slicer with the modified CT
MODIFIED_CT="$AMOS_DIR/${CASE_ID}_with_cyst.nii.gz"
if [ ! -f "$MODIFIED_CT" ]; then
    MODIFIED_CT="$AMOS_DIR/${CASE_ID}.nii.gz"
fi

echo "Launching 3D Slicer with CT scan..."
if [ -f "$MODIFIED_CT" ]; then
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$MODIFIED_CT" > /tmp/slicer_launch.log 2>&1 &
else
    echo "ERROR: CT file not found!"
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
fi

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f Slicer > /dev/null && DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi slicer; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for full load
sleep 10

# Maximize and focus window
echo "Configuring Slicer window..."
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Renal Cyst Bosniak Classification"
echo "========================================"
echo ""
echo "An abdominal CT scan is loaded. A renal cyst has been identified."
echo "Your task is to characterize this cystic lesion using the Bosniak system."
echo ""
echo "Steps:"
echo "  1. Navigate to the right kidney and locate the cyst"
echo "  2. Measure maximum diameter using a ruler/line markup"
echo "  3. Measure internal HU using an ROI"
echo "  4. Measure reference kidney parenchyma HU"
echo "  5. Assess wall, septa, calcifications"
echo "  6. Classify using Bosniak criteria (I, II, IIF, III, IV)"
echo ""
echo "Save outputs:"
echo "  - Measurements: ~/Documents/SlicerData/AMOS/cyst_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/bosniak_report.json"
echo ""