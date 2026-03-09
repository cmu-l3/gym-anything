#!/bin/bash
echo "=== Setting up Vertebral Compression Ratio Measurement Task ==="

# Source task utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date)"

# Directories
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Ensure proper permissions
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true

# Clear any previous task results
rm -f "$EXPORTS_DIR/l1_compression_measurements.json" 2>/dev/null || true
rm -f /tmp/vcr_task_result.json 2>/dev/null || true

# Record initial state
ls -la "$EXPORTS_DIR"/*.json 2>/dev/null > /tmp/initial_exports.txt || echo "none" > /tmp/initial_exports.txt

# ============================================================
# Prepare spine CT data with known vertebral dimensions
# ============================================================
echo "Preparing spine CT data..."

# Install Python dependencies if needed
pip install -q numpy nibabel scipy 2>/dev/null || pip3 install -q numpy nibabel scipy 2>/dev/null || true

OUTPUT_CT="$AMOS_DIR/spine_ct.nii.gz"
GT_FILE="$GROUND_TRUTH_DIR/spine_measurements.json"

# Check if data already exists
if [ -f "$OUTPUT_CT" ] && [ -f "$GT_FILE" ]; then
    echo "Spine data already exists, skipping generation"
else
    echo "Generating synthetic spine CT with known vertebral body dimensions..."
    
    python3 << 'PYEOF'
import os
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

from scipy.ndimage import gaussian_filter

amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"
output_ct = os.path.join(amos_dir, "spine_ct.nii.gz")
gt_file = os.path.join(gt_dir, "spine_measurements.json")

np.random.seed(42)

# Image dimensions and spacing
# Create a volume that shows spine in sagittal orientation
nx, ny, nz = 256, 256, 100  # Sagittal primary
spacing = (1.0, 1.0, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

print(f"Creating spine CT volume: {nx}x{ny}x{nz} voxels, spacing {spacing}mm")

# Initialize with soft tissue background
ct_data = np.random.normal(40, 10, (nx, ny, nz)).astype(np.int16)

# Define vertebral body parameters
# L1 is our target - anterior slightly lower (simulating normal/borderline)
vertebrae = {
    'T11': {'center_z': 85, 'height_ant': 24.0, 'height_post': 25.0},
    'T12': {'center_z': 72, 'height_ant': 26.0, 'height_post': 26.5, 'has_ribs': True},
    'L1':  {'center_z': 58, 'height_ant': 28.5, 'height_post': 32.0},  # TARGET
    'L2':  {'center_z': 44, 'height_ant': 30.0, 'height_post': 31.0},
    'L3':  {'center_z': 30, 'height_ant': 31.0, 'height_post': 31.5},
    'L4':  {'center_z': 16, 'height_ant': 30.5, 'height_post': 31.0},
}

# Vertebral body dimensions
vb_ap_depth_mm = 35
vb_lateral_mm = 45
vb_ap_vox = vb_ap_depth_mm / spacing[0]
vb_lateral_vox = vb_lateral_mm / spacing[1]

# Center position
center_x = nx // 2
center_y = ny // 2

# Create each vertebra
for name, params in vertebrae.items():
    center_z = params['center_z']
    h_ant = params['height_ant'] / spacing[2]
    h_post = params['height_post'] / spacing[2]
    
    z_top = int(center_z + max(h_ant, h_post) / 2)
    z_bot = int(center_z - max(h_ant, h_post) / 2)
    
    for z in range(max(0, z_bot), min(nz, z_top + 1)):
        for x in range(nx):
            for y in range(ny):
                x_norm = (x - center_x) / (vb_ap_vox / 2)
                y_norm = (y - center_y) / (vb_lateral_vox / 2)
                
                if x_norm**2 + y_norm**2 <= 1.0:
                    t = (x_norm + 1) / 2
                    local_height = h_post + t * (h_ant - h_post)
                    z_local = z - center_z
                    
                    if abs(z_local) <= local_height / 2:
                        dist_from_edge = min(1 - abs(x_norm), 1 - abs(y_norm))
                        if dist_from_edge < 0.15:
                            ct_data[x, y, z] = int(np.random.normal(800, 50))
                        else:
                            ct_data[x, y, z] = int(np.random.normal(250, 30))
    
    # Posterior elements
    sp_x = center_x - int(vb_ap_vox / 2) - 15
    for z in range(max(0, z_bot + 2), min(nz, z_top - 2)):
        for dx in range(-3, 4):
            for dy in range(-2, 3):
                x = sp_x + dx
                y = center_y + dy
                if 0 <= x < nx and 0 <= y < ny:
                    ct_data[x, y, z] = int(np.random.normal(600, 50))
    
    # Add ribs for T12
    if params.get('has_ribs', False):
        rib_z = center_z
        for side in [-1, 1]:
            rib_y = center_y + side * int(vb_lateral_vox / 2 + 5)
            for dx in range(-20, 5):
                for dy in range(-2, 3):
                    x = center_x + dx
                    y = rib_y + dy
                    z = rib_z + int(dy * 0.3)
                    if 0 <= x < nx and 0 <= y < ny and 0 <= z < nz:
                        ct_data[x, y, z] = int(np.random.normal(700, 50))

# Add intervertebral discs
disc_levels = [('T11-T12', 79), ('T12-L1', 65), ('L1-L2', 51), ('L2-L3', 37), ('L3-L4', 23)]
for disc_name, disc_z in disc_levels:
    for x in range(nx):
        for y in range(ny):
            x_norm = (x - center_x) / (vb_ap_vox / 2)
            y_norm = (y - center_y) / (vb_lateral_vox / 2)
            if x_norm**2 + y_norm**2 <= 0.85:
                for dz in range(-2, 3):
                    z = disc_z + dz
                    if 0 <= z < nz:
                        ct_data[x, y, z] = int(np.random.normal(80, 15))

# Add spinal canal
canal_radius = 6
for z in range(nz):
    for x in range(center_x - 20, center_x - 10):
        for y in range(center_y - canal_radius, center_y + canal_radius + 1):
            if (y - center_y)**2 <= canal_radius**2:
                ct_data[x, y, z] = int(np.random.normal(10, 5))

# Add paraspinal muscles
for side in [-1, 1]:
    muscle_y = center_y + side * int(vb_lateral_vox / 2 + 15)
    for z in range(nz):
        for dx in range(-25, -5):
            for dy in range(-10, 11):
                x = center_x + dx
                y = muscle_y + dy
                if 0 <= x < nx and 0 <= y < ny:
                    dist = np.sqrt(dx**2 + dy**2)
                    if dist < 15:
                        ct_data[x, y, z] = int(np.random.normal(45, 8))

# Apply smoothing
ct_data = gaussian_filter(ct_data.astype(np.float32), sigma=0.5).astype(np.int16)

# Save NIfTI
ct_nii = nib.Nifti1Image(ct_data, affine)
nib.save(ct_nii, output_ct)
print(f"Spine CT saved to {output_ct}")

# Save ground truth
l1_params = vertebrae['L1']
gt_ratio = l1_params['height_ant'] / l1_params['height_post']

if gt_ratio >= 0.85:
    classification = "Normal"
elif gt_ratio >= 0.75:
    classification = "Mild"
elif gt_ratio >= 0.60:
    classification = "Moderate"
else:
    classification = "Severe"

ground_truth = {
    "vertebral_level": "L1",
    "anterior_height_mm": l1_params['height_ant'],
    "posterior_height_mm": l1_params['height_post'],
    "compression_ratio": round(gt_ratio, 4),
    "classification": classification,
    "l1_center_slice": l1_params['center_z'],
    "t12_has_ribs": True,
    "volume_shape": list(ct_data.shape),
    "spacing_mm": list(spacing)
}

with open(gt_file, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved: {gt_file}")
print(f"L1 anterior height: {l1_params['height_ant']:.1f} mm")
print(f"L1 posterior height: {l1_params['height_post']:.1f} mm")
print(f"Compression ratio: {gt_ratio:.4f} ({classification})")
PYEOF
fi

# Verify data was created
if [ ! -f "$OUTPUT_CT" ]; then
    echo "ERROR: Failed to create spine CT data"
    exit 1
fi

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer with spine data
# ============================================================
echo "Launching 3D Slicer with spine CT..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Ensure X display
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer with the spine CT file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$OUTPUT_CT' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Maximize and focus Slicer
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo "Spine CT loaded: $OUTPUT_CT"
echo "Export directory: $EXPORTS_DIR"
echo ""
echo "TASK: Measure L1 vertebral compression ratio"
echo "  1. Navigate to sagittal view of L1 (below T12 which has ribs)"
echo "  2. Measure anterior height (front edge, top to bottom)"
echo "  3. Measure posterior height (back edge, top to bottom)"
echo "  4. Calculate ratio and classify"
echo "  5. Save to: $EXPORTS_DIR/l1_compression_measurements.json"