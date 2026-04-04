#!/bin/bash
echo "=== Setting up Adrenal Incidentaloma Characterization Task ==="

source /workspace/scripts/task_utils.sh

ADRENAL_DIR="/home/ga/Documents/SlicerData/Adrenal"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$ADRENAL_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f "$ADRENAL_DIR/nodule_measurement.mrk.json" 2>/dev/null || true
rm -f "$ADRENAL_DIR/density_roi.mrk.json" 2>/dev/null || true
rm -f "$ADRENAL_DIR/adrenal_report.json" 2>/dev/null || true
rm -f /tmp/adrenal_task_result.json 2>/dev/null || true

# Generate synthetic abdominal CT with adrenal nodule
echo "Generating synthetic abdominal CT with adrenal nodule..."

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

adrenal_dir = "/home/ga/Documents/SlicerData/Adrenal"
gt_dir = "/var/lib/slicer/ground_truth"

# Use a seed based on current time for some randomization
np.random.seed(int(os.popen("date +%s").read()) % 10000)

# CT volume parameters - realistic abdominal CT
nx, ny, nz = 256, 256, 120
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

print(f"Creating synthetic abdominal CT: {nx}x{ny}x{nz}, spacing={spacing}")

# Initialize CT volume with soft tissue background
ct_data = np.random.normal(40, 12, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_mask = ((X - center_x)**2 / (95**2) + (Y - center_y)**2 / (75**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (vertebral body)
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask & body_mask] = np.random.normal(450, 60, (np.sum(spine_mask & body_mask),)).astype(np.int16)

# Create kidneys (paired organs, adrenals sit on top)
# Right kidney (patient's right = image left)
right_kidney_cx, right_kidney_cy = center_x - 45, center_y + 15
# Left kidney
left_kidney_cx, left_kidney_cy = center_x + 45, center_y + 15

for z in range(30, 100):
    # Create kidney shapes (elliptical)
    for k_cx, k_cy in [(right_kidney_cx, right_kidney_cy), (left_kidney_cx, left_kidney_cy)]:
        # Vary size along z
        z_factor = 1.0 - 0.3 * abs(z - 65) / 35
        if z_factor > 0:
            kidney_mask = ((X - k_cx)**2 / (20 * z_factor)**2 + (Y - k_cy)**2 / (30 * z_factor)**2) <= 1.0
            # Kidney parenchyma ~30-40 HU
            ct_data[:, :, z][kidney_mask & body_mask] = np.random.normal(35, 8, (np.sum(kidney_mask & body_mask),)).astype(np.int16)

# Create adrenal glands (triangular/Y-shaped, superior-medial to kidneys)
# Right adrenal
right_adrenal_cx, right_adrenal_cy = center_x - 25, center_y + 25
# Left adrenal
left_adrenal_cx, left_adrenal_cy = center_x + 25, center_y + 25

# Normal adrenal tissue ~25-40 HU, limbs are thin
adrenal_z_range = range(75, 100)
for z in adrenal_z_range:
    z_factor = 1.0 - 0.5 * abs(z - 87) / 12
    if z_factor > 0:
        for a_cx, a_cy in [(right_adrenal_cx, right_adrenal_cy), (left_adrenal_cx, left_adrenal_cy)]:
            # Create triangular adrenal shape
            adrenal_mask = ((X - a_cx)**2 + (Y - a_cy)**2) <= (6 * z_factor)**2
            ct_data[:, :, z][adrenal_mask & body_mask] = np.random.normal(30, 5, (np.sum(adrenal_mask & body_mask),)).astype(np.int16)

# ============================================================
# CREATE THE ADRENAL NODULE (main task element)
# ============================================================
# Randomize nodule properties
laterality = np.random.choice(["left", "right"])
nodule_diameter_mm = np.random.uniform(14, 42)  # 14-42mm covers all classifications
nodule_hu = np.random.uniform(-8, 48)  # -8 to 48 HU covers lipid-rich to indeterminate

# Convert diameter to voxels
nodule_radius_voxels = (nodule_diameter_mm / 2.0) / spacing[0]

# Place nodule in the selected adrenal
if laterality == "right":
    nodule_cx, nodule_cy = right_adrenal_cx, right_adrenal_cy
else:
    nodule_cx, nodule_cy = left_adrenal_cx, left_adrenal_cy

# Place nodule at a specific z level
nodule_z = 88  # Central in adrenal z range
nodule_center = [nodule_cx, nodule_cy, nodule_z]

print(f"Creating adrenal nodule:")
print(f"  Laterality: {laterality}")
print(f"  Diameter: {nodule_diameter_mm:.1f} mm ({nodule_radius_voxels:.1f} voxels radius)")
print(f"  HU density: {nodule_hu:.1f}")
print(f"  Center: {nodule_center}")

# Create ellipsoidal nodule with slight irregularity
nodule_voxels = 0
for z in range(max(0, int(nodule_z - nodule_radius_voxels * 0.8)), min(nz, int(nodule_z + nodule_radius_voxels * 0.8) + 1)):
    for y in range(max(0, int(nodule_cy - nodule_radius_voxels - 2)), min(ny, int(nodule_cy + nodule_radius_voxels + 3))):
        for x in range(max(0, int(nodule_cx - nodule_radius_voxels - 2)), min(nx, int(nodule_cx + nodule_radius_voxels + 3))):
            # Ellipsoid equation with slight z-compression
            dx = (x - nodule_cx) / nodule_radius_voxels
            dy = (y - nodule_cy) / nodule_radius_voxels
            dz = (z - nodule_z) / (nodule_radius_voxels * 0.7)  # Compressed in z
            
            if dx**2 + dy**2 + dz**2 <= 1.0:
                if body_mask[x, y]:
                    # Add small internal variation
                    hu_value = nodule_hu + np.random.normal(0, 4)
                    ct_data[x, y, z] = int(hu_value)
                    nodule_voxels += 1

print(f"  Nodule voxels: {nodule_voxels}")

# Add liver for anatomical context (right side of abdomen)
liver_cx, liver_cy = center_x - 40, center_y - 15
for z in range(35, 95):
    z_factor = 1.0 - 0.4 * abs(z - 65) / 30
    if z_factor > 0:
        liver_mask = ((X - liver_cx)**2 / (50 * z_factor)**2 + (Y - liver_cy)**2 / (40 * z_factor)**2) <= 1.0
        # Exclude area where kidney is
        kidney_exclude = ((X - right_kidney_cx)**2 / 25**2 + (Y - right_kidney_cy)**2 / 35**2) <= 1.0
        liver_only = liver_mask & ~kidney_exclude & body_mask
        ct_data[:, :, z][liver_only] = np.random.normal(55, 10, (np.sum(liver_only),)).astype(np.int16)

# Add subcutaneous fat
fat_inner = ((X - center_x)**2 / (85**2) + (Y - center_y)**2 / (65**2)) <= 1.0
fat_outer = body_mask
fat_ring = fat_outer & ~fat_inner
for z in range(nz):
    ct_data[:, :, z][fat_ring] = np.random.normal(-85, 12, (np.sum(fat_ring),)).astype(np.int16)

# Save CT volume
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(adrenal_dir, "adrenal_ct.nii.gz")
nib.save(ct_nii, ct_path)
print(f"CT saved to: {ct_path}")

# ============================================================
# DETERMINE CORRECT CLASSIFICATION
# ============================================================
def classify_adrenal_nodule(size_mm, hu):
    """ACR Incidental Findings Committee classification."""
    if size_mm < 10:
        return "benign_adenoma"
    elif size_mm >= 40:
        return "concerning"
    elif hu <= 10:
        return "benign_adenoma"
    elif hu <= 30:
        return "likely_benign"
    else:
        return "indeterminate"

correct_classification = classify_adrenal_nodule(nodule_diameter_mm, nodule_hu)

# Clinical recommendations
recommendations = {
    "benign_adenoma": "No follow-up needed. Lipid-rich adenoma characteristics.",
    "likely_benign": "Consider optional 12-month follow-up CT or adrenal protocol CT for confirmation.",
    "indeterminate": "Recommend adrenal protocol CT with washout or MRI with chemical shift for characterization.",
    "concerning": "Recommend further imaging (CT/MRI) and consider adrenal biopsy or surgical consultation."
}

print(f"  Classification: {correct_classification}")

# Save ground truth
gt_data = {
    "laterality": laterality,
    "exact_diameter_mm": float(nodule_diameter_mm),
    "exact_density_hu": float(nodule_hu),
    "nodule_center_voxels": [int(nodule_cx), int(nodule_cy), int(nodule_z)],
    "nodule_center_mm": [
        float(nodule_cx * spacing[0]),
        float(nodule_cy * spacing[1]),
        float(nodule_z * spacing[2])
    ],
    "correct_classification": correct_classification,
    "correct_recommendation": recommendations[correct_classification],
    "voxel_spacing_mm": list(spacing),
    "volume_shape": [nx, ny, nz]
}

gt_path = os.path.join(gt_dir, "adrenal_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to: {gt_path}")

# Also copy ground truth to temp for export script
import shutil
shutil.copy(gt_path, "/tmp/adrenal_ground_truth.json")

print("\nData generation complete!")
PYEOF

# Verify data was created
CT_FILE="$ADRENAL_DIR/adrenal_ct.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not created!"
    exit 1
fi
echo "CT volume created: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

if [ ! -f "$GROUND_TRUTH_DIR/adrenal_gt.json" ]; then
    echo "ERROR: Ground truth not created!"
    exit 1
fi
echo "Ground truth created (hidden from agent)"

# Display ground truth info for debugging (won't be visible to agent)
echo ""
echo "=== Ground Truth (for verification) ==="
cat "$GROUND_TRUTH_DIR/adrenal_gt.json"
echo ""

# Create Slicer Python script to load CT with abdominal window
cat > /tmp/load_adrenal_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/Adrenal/adrenal_ct.nii.gz"

print(f"Loading abdominal CT: {ct_path}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set abdominal soft tissue window (W=350, L=40)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Center on approximate adrenal region (upper abdomen)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Position views to show upper abdomen where adrenals are located
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Calculate positions - focus on upper portion where adrenals are
        center_x = (bounds[0] + bounds[1]) / 2
        center_y = (bounds[2] + bounds[3]) / 2
        # Adrenals are typically in upper 1/3 of abdomen in z
        adrenal_z = bounds[4] + (bounds[5] - bounds[4]) * 0.75
        
        if color == "Red":  # Axial - show adrenal level
            sliceNode.SetSliceOffset(adrenal_z)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center_y)
        else:  # Sagittal
            sliceNode.SetSliceOffset(center_x)
    
    print(f"CT loaded with abdominal window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete - ready for adrenal nodule characterization")
PYEOF

# Kill any existing Slicer
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_adrenal_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to load
wait_for_slicer 120
sleep 8

# Configure window
echo "Configuring Slicer window..."

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
    
    focus_window "$WID"
fi

sleep 3

# Take initial screenshot
take_screenshot /tmp/adrenal_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Adrenal Incidentaloma Characterization"
echo "============================================="
echo ""
echo "A 58-year-old patient had a CT scan for unrelated symptoms."
echo "An incidental adrenal nodule has been noted. Characterize it."
echo ""
echo "Your tasks:"
echo "  1. Locate the adrenal glands (superior-medial to kidneys)"
echo "  2. Identify which side (left/right) has the nodule"
echo "  3. Measure the maximum diameter (mm) using a ruler"
echo "  4. Measure the mean HU density using an ROI"
echo "  5. Classify according to ACR guidelines"
echo ""
echo "ACR Classification:"
echo "  - Benign Adenoma: <10mm OR (<40mm AND HU<=10)"
echo "  - Likely Benign: 10-40mm AND HU 11-30"
echo "  - Indeterminate: 10-40mm AND HU>30"
echo "  - Concerning: >=40mm"
echo ""
echo "Save outputs to ~/Documents/SlicerData/Adrenal/"
echo ""