#!/bin/bash
echo "=== Setting up Emphysema Quantification Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Define directories
LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Clean up any previous task artifacts
echo "Cleaning up previous task artifacts..."
rm -f "$LIDC_DIR/lung_segmentation.nii.gz" 2>/dev/null || true
rm -f "$LIDC_DIR/lung_segmentation.nii" 2>/dev/null || true
rm -f "$LIDC_DIR/emphysema_report.json" 2>/dev/null || true
rm -f /tmp/emphysema_task_result.json 2>/dev/null || true

# Check if we have sample chest CT data
CT_FILE=""
if [ -f "/home/ga/Documents/SlicerData/SampleData/CTChest.nrrd" ]; then
    echo "Using CTChest sample data"
    CT_FILE="/home/ga/Documents/SlicerData/SampleData/CTChest.nrrd"
    cp "$CT_FILE" "$LIDC_DIR/chest_ct.nrrd" 2>/dev/null || true
    CT_FILE="$LIDC_DIR/chest_ct.nrrd"
elif [ -f "$LIDC_DIR/chest_ct.nii.gz" ]; then
    echo "Using existing chest CT"
    CT_FILE="$LIDC_DIR/chest_ct.nii.gz"
else
    echo "Generating synthetic chest CT with emphysema..."
    # Generate synthetic chest CT data with known emphysema
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

lidc_dir = "/home/ga/Documents/SlicerData/LIDC"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Realistic chest CT dimensions
nx, ny, nz = 512, 512, 180
spacing = (0.7, 0.7, 2.5)  # mm

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

print("Generating synthetic chest CT with emphysema...")

# Initialize with air
ct_data = np.full((nx, ny, nz), -1000, dtype=np.int16)

# Create body outline (elliptical thorax)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Thorax shape varies along z
for z in range(nz):
    # Slightly larger in middle of thorax
    z_factor = 1.0 - 0.1 * abs(z - nz//2) / (nz//2)
    rx = 150 * z_factor
    ry = 120 * z_factor
    
    body_mask = ((X - center_x)**2 / (rx**2) + (Y - center_y)**2 / (ry**2)) <= 1.0
    ct_data[:, :, z][body_mask] = np.random.normal(40, 10, np.sum(body_mask)).astype(np.int16)

# Create lungs (two separate regions)
lung_mask = np.zeros((nx, ny, nz), dtype=bool)

for z in range(15, nz - 15):
    z_factor = 1.0 - 0.15 * abs(z - nz//2) / (nz//2)
    
    # Right lung (larger)
    r_lung_cx = center_x - 70
    r_lung_cy = center_y
    r_lung_rx = 80 * z_factor
    r_lung_ry = 90 * z_factor
    r_lung = ((X - r_lung_cx)**2 / (r_lung_rx**2) + (Y - r_lung_cy)**2 / (r_lung_ry**2)) <= 1.0
    
    # Left lung (smaller due to heart)
    l_lung_cx = center_x + 70
    l_lung_cy = center_y + 10
    l_lung_rx = 70 * z_factor
    l_lung_ry = 80 * z_factor
    l_lung = ((X - l_lung_cx)**2 / (l_lung_rx**2) + (Y - l_lung_cy)**2 / (l_lung_ry**2)) <= 1.0
    
    lung_mask[:, :, z] = r_lung | l_lung

# Fill lungs with varying density
# Target ~18% LAA-950 (moderate emphysema)
emphysema_severity = 0.18

for z in range(nz):
    slice_lung = lung_mask[:, :, z]
    if not np.any(slice_lung):
        continue
    
    # Upper lobes have more emphysema (centrilobular pattern)
    z_position = z / nz
    if z_position > 0.5:  # Upper half
        regional_emphysema = emphysema_severity * 1.5
    else:
        regional_emphysema = emphysema_severity * 0.6
    
    # Generate lung densities
    lung_coords = np.where(slice_lung)
    n_lung_voxels = len(lung_coords[0])
    
    # Create baseline lung density
    baseline_density = np.random.normal(-850, 50, n_lung_voxels)
    
    # Add emphysematous regions
    emphysema_mask = np.random.random(n_lung_voxels) < regional_emphysema
    baseline_density[emphysema_mask] = np.random.normal(-970, 15, np.sum(emphysema_mask))
    
    # Add some healthy patches too
    healthy_mask = np.random.random(n_lung_voxels) < 0.1
    baseline_density[healthy_mask] = np.random.normal(-750, 30, np.sum(healthy_mask))
    
    ct_data[lung_coords[0], lung_coords[1], z] = np.clip(baseline_density, -1024, -200).astype(np.int16)

# Add mediastinum and heart
for z in range(25, nz - 25):
    # Mediastinum (central)
    med_mask = ((X - center_x)**2 + (Y - center_y)**2) <= 35**2
    ct_data[:, :, z][med_mask & ~lung_mask[:, :, z]] = np.random.normal(45, 15, np.sum(med_mask & ~lung_mask[:, :, z])).astype(np.int16)
    
    # Heart (left side)
    heart_cx = center_x + 40
    heart_cy = center_y
    heart_mask = ((X - heart_cx)**2 / (45**2) + (Y - heart_cy)**2 / (50**2)) <= 1.0
    if z > nz//3 and z < 2*nz//3:
        ct_data[:, :, z][heart_mask] = np.random.normal(50, 10, np.sum(heart_mask)).astype(np.int16)

# Add spine (posterior)
for z in range(nz):
    spine_cx = center_x
    spine_cy = center_y + 110
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 18**2
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 80, np.sum(spine_mask)).astype(np.int16)

# Add ribs (surrounding lungs)
for z in range(8, nz - 8):
    if z % 12 < 4:  # Every ~3cm
        z_factor = 1.0 - 0.1 * abs(z - nz//2) / (nz//2)
        for angle in np.linspace(0.2, np.pi - 0.2, 8):
            rx = 160 * z_factor
            ry = 130 * z_factor
            rib_x = int(center_x + rx * np.cos(angle))
            rib_y = int(center_y + ry * np.sin(angle))
            rib_mask = ((X - rib_x)**2 + (Y - rib_y)**2) <= 5**2
            ct_data[:, :, z][rib_mask] = np.random.normal(500, 100, np.sum(rib_mask)).astype(np.int16)

# Add main airways as NOT part of lung (air-filled)
for z in range(35, nz):
    # Trachea
    trachea_mask = ((X - center_x)**2 + (Y - center_y - 20)**2) <= 8**2
    ct_data[:, :, z][trachea_mask] = -1000  # Air

# Save CT volume
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(lidc_dir, "chest_ct.nii.gz")
nib.save(ct_img, ct_path)
print(f"Synthetic CT saved: {ct_path}")

# ============================================================
# Compute and save ground truth
# ============================================================

# Ground truth lung mask
gt_lung_img = nib.Nifti1Image(lung_mask.astype(np.int16), affine)
gt_lung_path = os.path.join(gt_dir, "lung_mask_gt.nii.gz")
nib.save(gt_lung_img, gt_lung_path)

# Compute ground truth metrics
lung_voxels = ct_data[lung_mask]
total_lung_voxels = len(lung_voxels)
voxel_volume_ml = np.prod(spacing) / 1000.0

emphysema_voxels = np.sum(lung_voxels < -950)
laa_950 = 100.0 * emphysema_voxels / total_lung_voxels

total_lung_volume_ml = total_lung_voxels * voxel_volume_ml
mean_lung_density = float(np.mean(lung_voxels))
perc15_density = float(np.percentile(lung_voxels, 15))

# Classification
if laa_950 < 6:
    classification = "Normal"
elif laa_950 < 15:
    classification = "Mild"
elif laa_950 < 25:
    classification = "Moderate"
else:
    classification = "Severe"

gt_data = {
    "patient_id": "synthetic_emphysema",
    "total_lung_volume_ml": round(total_lung_volume_ml, 1),
    "total_lung_voxels": int(total_lung_voxels),
    "emphysema_voxels": int(emphysema_voxels),
    "laa_950_percent": round(laa_950, 2),
    "severity_classification": classification,
    "mean_lung_density_hu": round(mean_lung_density, 1),
    "perc15_density_hu": round(perc15_density, 1),
    "voxel_spacing_mm": list(spacing),
    "volume_shape": list(ct_data.shape)
}

gt_path = os.path.join(gt_dir, "emphysema_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved: {gt_path}")
print(f"  Total lung volume: {total_lung_volume_ml:.1f} mL")
print(f"  LAA-950: {laa_950:.2f}%")
print(f"  Classification: {classification}")
print(f"  Mean density: {mean_lung_density:.1f} HU")
print(f"  15th percentile: {perc15_density:.1f} HU")
PYEOF
    
    CT_FILE="$LIDC_DIR/chest_ct.nii.gz"
fi

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi

echo "CT file prepared: $CT_FILE"
echo "$CT_FILE" > /tmp/emphysema_ct_file.txt

# Set permissions
chown -R ga:ga "$LIDC_DIR" 2>/dev/null || true
chmod -R 755 "$LIDC_DIR" 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Python script to load CT with proper window/level
cat > /tmp/load_chest_ct.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/LIDC/chest_ct.nii.gz")

print(f"Loading chest CT: {ct_path}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set lung window/level for optimal visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard lung window
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-600)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on data
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
    
    print(f"CT loaded with lung window (W=1500, L=-600)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for emphysema quantification task")
PYEOF

# Launch 3D Slicer with the CT data
echo "Launching 3D Slicer with chest CT..."
export CT_FILE
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to load..."
sleep 10

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
sleep 10

# Maximize and focus window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    echo "Found Slicer window: $SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    sleep 1
fi

# Dismiss any dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Emphysema Quantification Task Setup Complete ==="
echo ""
echo "TASK: COPD Emphysema Quantification"
echo "===================================="
echo ""
echo "You are given a chest CT scan. Quantify emphysema severity:"
echo ""
echo "1. Segment both lungs using Segment Editor"
echo "   - Lung threshold: -1024 to -250 HU"
echo "   - Exclude airways, vessels, mediastinum"
echo ""
echo "2. Calculate LAA-950 (Low Attenuation Area):"
echo "   - LAA-950 = % of lung voxels below -950 HU"
echo ""
echo "3. Classify severity:"
echo "   - Normal: < 6%"
echo "   - Mild: 6-14%"
echo "   - Moderate: 15-24%"
echo "   - Severe: >= 25%"
echo ""
echo "Save outputs:"
echo "  Segmentation: ~/Documents/SlicerData/LIDC/lung_segmentation.nii.gz"
echo "  Report: ~/Documents/SlicerData/LIDC/emphysema_report.json"
echo ""