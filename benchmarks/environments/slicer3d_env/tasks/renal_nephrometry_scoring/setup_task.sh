#!/bin/bash
echo "=== Setting up Renal Nephrometry Scoring Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

KITS_DIR="/home/ga/Documents/SlicerData/KiTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="case_00002"

# Create directories
mkdir -p "$KITS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clear any previous outputs
rm -f "$KITS_DIR/agent_measurements.mrk.json" 2>/dev/null || true
rm -f "$KITS_DIR/renal_score_report.json" 2>/dev/null || true
rm -f /tmp/renal_task_result.json 2>/dev/null || true

# Prepare KiTS data
echo "Preparing KiTS kidney CT data..."

# Check if data already exists
if [ -f "$KITS_DIR/${CASE_ID}_imaging.nii.gz" ] && [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_renal_gt.json" ]; then
    echo "KiTS data already exists for $CASE_ID"
else
    echo "Generating kidney CT with tumor..."
    
    # Ensure Python dependencies
    pip install -q numpy nibabel scipy 2>/dev/null || pip3 install -q numpy nibabel scipy 2>/dev/null || true
    
    # Generate synthetic KiTS-like data with known ground truth
    python3 << 'PYEOF'
import numpy as np
import os
import json

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

from scipy.ndimage import distance_transform_edt, label as scipy_label

case_id = "case_00002"
kits_dir = "/home/ga/Documents/SlicerData/KiTS"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Realistic abdominal CT parameters
nx, ny, nz = 256, 256, 100
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize CT with soft tissue
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)
seg_data = np.zeros((nx, ny, nz), dtype=np.uint8)

# Create body outline
Y, X = np.ogrid[:nx, :ny]
center = (nx // 2, ny // 2)
body_mask = ((X - center[0])**2 / 140**2 + (Y - center[1])**2 / 100**2) <= 1.0

for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (posterior)
spine_cx, spine_cy = center[0], center[1] + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask] = np.random.normal(500, 80, np.sum(spine_mask)).astype(np.int16)

# Create RIGHT kidney
kidney_r_cx, kidney_r_cy = center[0] - 70, center[1] + 15
kidney_r_z_center = 55
kidney_r_z_extent = 30

# Create LEFT kidney (will have the tumor)
kidney_l_cx, kidney_l_cy = center[0] + 70, center[1] + 15
kidney_l_z_center = 55
kidney_l_z_extent = 30

# Draw kidneys
for z in range(nz):
    # Right kidney
    z_factor_r = 1.0 - ((z - kidney_r_z_center)**2) / (kidney_r_z_extent**2)
    if z_factor_r > 0:
        z_factor_r = np.sqrt(z_factor_r)
        r_mask = ((X - kidney_r_cx)**2 / (35 * z_factor_r + 0.1)**2 + 
                  (Y - kidney_r_cy)**2 / (22 * z_factor_r + 0.1)**2) <= 1.0
        ct_data[:, :, z][r_mask & body_mask] = np.random.normal(35, 12, np.sum(r_mask & body_mask)).astype(np.int16)
        seg_data[:, :, z][r_mask & body_mask] = 1  # kidney label
    
    # Left kidney
    z_factor_l = 1.0 - ((z - kidney_l_z_center)**2) / (kidney_l_z_extent**2)
    if z_factor_l > 0:
        z_factor_l = np.sqrt(z_factor_l)
        l_mask = ((X - kidney_l_cx)**2 / (35 * z_factor_l + 0.1)**2 + 
                  (Y - kidney_l_cy)**2 / (22 * z_factor_l + 0.1)**2) <= 1.0
        ct_data[:, :, z][l_mask & body_mask] = np.random.normal(35, 12, np.sum(l_mask & body_mask)).astype(np.int16)
        seg_data[:, :, z][l_mask & body_mask] = 1  # kidney label

# Create TUMOR on left kidney
# Tumor parameters: 4.5cm diameter, 40% exophytic, posterior, lower pole
tumor_diameter_cm = 4.5
tumor_radius_mm = tumor_diameter_cm * 10 / 2
tumor_radius_voxels = tumor_radius_mm / spacing[0]  # ~29 voxels

# Position: posterior-lateral on left kidney, lower pole
tumor_cx = kidney_l_cx + 20  # Lateral
tumor_cy = kidney_l_cy + 18  # Posterior
tumor_cz = kidney_l_z_center - 12  # Lower pole

# Create tumor
for z in range(int(tumor_cz - tumor_radius_voxels - 5), int(tumor_cz + tumor_radius_voxels + 5)):
    if 0 <= z < nz:
        for x in range(int(tumor_cx - tumor_radius_voxels - 5), int(tumor_cx + tumor_radius_voxels + 5)):
            for y in range(int(tumor_cy - tumor_radius_voxels - 5), int(tumor_cy + tumor_radius_voxels + 5)):
                if 0 <= x < nx and 0 <= y < ny:
                    # Ellipsoidal tumor
                    dist = np.sqrt((x - tumor_cx)**2 + (y - tumor_cy)**2 + 
                                   ((z - tumor_cz) * spacing[2] / spacing[0])**2)
                    if dist <= tumor_radius_voxels:
                        ct_data[x, y, z] = np.random.normal(65, 20)  # Slightly enhanced tumor
                        seg_data[x, y, z] = 2  # Tumor label

# Save CT volume
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(kits_dir, f"{case_id}_imaging.nii.gz")
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path}")

# Save segmentation (ground truth - hidden)
seg_img = nib.Nifti1Image(seg_data, affine)
seg_path = os.path.join(gt_dir, f"{case_id}_segmentation.nii.gz")
nib.save(seg_img, seg_path)
print(f"Segmentation saved: {seg_path}")

# Compute ground truth RENAL score
tumor_mask = (seg_data == 2)
kidney_mask = (seg_data == 1) | (seg_data == 2)

tumor_coords = np.argwhere(tumor_mask)
tumor_centroid = tumor_coords.mean(axis=0)

# R Score: Maximum diameter
tumor_min = tumor_coords.min(axis=0)
tumor_max = tumor_coords.max(axis=0)
dims_mm = (tumor_max - tumor_min) * np.array(spacing)
max_diameter_cm = float(max(dims_mm) / 10.0)

if max_diameter_cm <= 4:
    r_score = 1
elif max_diameter_cm <= 7:
    r_score = 2
else:
    r_score = 3

# E Score: Exophytic percentage
kidney_only = (seg_data == 1)
tumor_in_kidney = np.sum(tumor_mask & kidney_only)
tumor_total = np.sum(tumor_mask)
# Exophytic = tumor extending beyond kidney
tumor_outside = tumor_total - tumor_in_kidney
exophytic_percent = float(100 * tumor_outside / tumor_total) if tumor_total > 0 else 50

if exophytic_percent >= 50:
    e_score = 1
elif exophytic_percent > 0:
    e_score = 2
else:
    e_score = 3

# N Score: Nearness to collecting system (approximate by kidney center)
left_kidney_mask = kidney_mask.copy()
# Find centroid of left kidney only
left_kidney_coords = np.argwhere(left_kidney_mask)
if len(left_kidney_coords) > 0:
    kidney_centroid = left_kidney_coords.mean(axis=0)
    
    # Distance from tumor surface to kidney interior
    kidney_interior = kidney_only
    if np.any(kidney_interior):
        kidney_dt = distance_transform_edt(~kidney_interior, sampling=spacing)
        tumor_surface_distances = kidney_dt[tumor_mask]
        nearness_mm = float(np.min(tumor_surface_distances)) if len(tumor_surface_distances) > 0 else 10
    else:
        nearness_mm = 8.0
else:
    nearness_mm = 8.0
    kidney_centroid = np.array([tumor_cx, tumor_cy, tumor_cz])

if nearness_mm >= 7:
    n_score = 1
elif nearness_mm > 4:
    n_score = 2
else:
    n_score = 3

# A Location: Anterior/Posterior
if tumor_centroid[1] > kidney_centroid[1] + 8:
    a_location = "p"  # Posterior
elif tumor_centroid[1] < kidney_centroid[1] - 8:
    a_location = "a"  # Anterior
else:
    a_location = "x"  # Neither

# L Score: Location relative to polar lines
kidney_z_coords = left_kidney_coords[:, 2] if len(left_kidney_coords) > 0 else [tumor_cz]
z_min, z_max = min(kidney_z_coords), max(kidney_z_coords)
z_range = z_max - z_min if z_max > z_min else 1
upper_line = z_max - z_range / 3
lower_line = z_min + z_range / 3

tumor_z_coords = tumor_coords[:, 2]
tumor_z_min, tumor_z_max = tumor_z_coords.min(), tumor_z_coords.max()

entirely_polar = tumor_z_min > upper_line or tumor_z_max < lower_line
crosses_upper = tumor_z_max > upper_line and tumor_z_min < upper_line
crosses_lower = tumor_z_max > lower_line and tumor_z_min < lower_line

if entirely_polar:
    l_score = 1
elif crosses_upper or crosses_lower:
    l_score = 2
else:
    l_score = 3

# Total score and complexity
total_score = r_score + e_score + n_score + l_score

if total_score <= 6:
    complexity = "Low"
elif total_score <= 9:
    complexity = "Moderate"
else:
    complexity = "High"

# Save ground truth
gt = {
    "tumor_side": "left",
    "R_diameter_cm": round(max_diameter_cm, 1),
    "R_score": int(r_score),
    "E_percent_exophytic": round(exophytic_percent, 0),
    "E_score": int(e_score),
    "N_distance_mm": round(nearness_mm, 1),
    "N_score": int(n_score),
    "A_location": a_location,
    "L_score": int(l_score),
    "total_score": int(total_score),
    "suffix": a_location,
    "complexity": complexity,
    "tumor_centroid_voxels": [float(x) for x in tumor_centroid],
    "tumor_volume_ml": float(np.sum(tumor_mask) * np.prod(spacing) / 1000)
}

gt_path = os.path.join(gt_dir, f"{case_id}_renal_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nGround truth RENAL score saved to {gt_path}")
print(f"RENAL Score: {total_score}{a_location} ({complexity} complexity)")
print(f"  R: {r_score} ({max_diameter_cm:.1f} cm)")
print(f"  E: {e_score} ({exophytic_percent:.0f}% exophytic)")
print(f"  N: {n_score} ({nearness_mm:.1f} mm)")
print(f"  A: {a_location}")
print(f"  L: {l_score}")
PYEOF
fi

# Save case ID
echo "$CASE_ID" > /tmp/kits_case_id

# Set permissions
chown -R ga:ga "$KITS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

CT_FILE="$KITS_DIR/${CASE_ID}_imaging.nii.gz"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_renal_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Create Slicer Python script to load the CT
cat > /tmp/load_kits_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/KiTS/case_00002_imaging.nii.gz"

print("Loading kidney CT scan...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT_Kidney")
    
    # Set abdominal soft tissue window
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on the data
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with abdominal window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for RENAL nephrometry scoring task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with kidney CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_kits_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to initialize..."
for i in {1..90}; do
    if pgrep -f "Slicer" > /dev/null; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Additional wait for module loading
sleep 15

# Maximize Slicer window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Renal Mass RENAL Nephrometry Scoring"
echo "============================================"
echo ""
echo "You are given an abdominal CT scan with a kidney tumor."
echo "Calculate the RENAL nephrometry score using these components:"
echo ""
echo "  R: Maximum tumor diameter (1: ≤4cm, 2: >4-7cm, 3: >7cm)"
echo "  E: Exophytic extent (1: ≥50%, 2: <50%, 3: endophytic)"
echo "  N: Nearness to sinus (1: ≥7mm, 2: 4-7mm, 3: ≤4mm)"
echo "  A: Anterior/Posterior (a, p, or x)"
echo "  L: Polar line location (1: polar, 2: crosses, 3: midline)"
echo ""
echo "Save your outputs:"
echo "  - Measurements: ~/Documents/SlicerData/KiTS/agent_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/KiTS/renal_score_report.json"
echo ""