#!/bin/bash
echo "=== Setting up Aortic Tortuosity Index Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_tortuous_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean any previous outputs
rm -f "$AMOS_DIR/aorta_centerline.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/tortuosity_report.json" 2>/dev/null || true
rm -f /tmp/tortuosity_task_result.json 2>/dev/null || true

# Generate synthetic CT data with known tortuous aorta
echo "Generating synthetic abdominal CT with tortuous aorta..."

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

case_id = "amos_tortuous_0001"
amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# CT volume parameters - realistic abdominal CT
nx, ny, nz = 256, 256, 120
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize CT volume with soft tissue background
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (80**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (vertebral body)
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask] = np.random.normal(450, 80, (np.sum(spine_mask),)).astype(np.int16)

# ============================================================
# Create TORTUOUS AORTA with sinusoidal path
# This gives us exact ground truth for tortuosity calculation
# ============================================================

# Aorta parameters
aorta_radius_mm = 12.0  # ~24mm diameter
aorta_radius_voxels = aorta_radius_mm / spacing[0]

# Centerline parameters - sinusoidal deviation from straight line
# Aorta runs from z=10 (superior) to z=110 (inferior, at bifurcation)
z_start = 10
z_end = 110
n_centerline_pts = 100

# Base position (anterior to spine)
base_x = center_x
base_y = center_y + 25

# Sinusoidal deviation amplitude and frequency
# Higher amplitude = more tortuosity
amplitude_voxels = 15.0  # deviation in voxels (~12mm)
frequency = 1.5  # number of complete oscillations

# Generate centerline points
z_values = np.linspace(z_start, z_end, n_centerline_pts)
t_normalized = (z_values - z_start) / (z_end - z_start)  # 0 to 1

# Sinusoidal x-deviation (lateral)
x_deviation = amplitude_voxels * np.sin(2 * np.pi * frequency * t_normalized)

# Also add some anterior-posterior deviation
y_deviation = (amplitude_voxels * 0.5) * np.sin(2 * np.pi * (frequency * 0.7) * t_normalized + np.pi/4)

# Centerline in voxel coordinates
centerline_x = base_x + x_deviation
centerline_y = base_y + y_deviation
centerline_z = z_values

# Convert to mm for ground truth
centerline_mm = np.column_stack([
    centerline_x * spacing[0],
    centerline_y * spacing[1],
    centerline_z * spacing[2]
])

# Calculate ground truth measurements
# Chord length: straight line from first to last point
chord_length = np.linalg.norm(centerline_mm[-1] - centerline_mm[0])

# Arc length: sum of segment lengths
arc_length = 0.0
for i in range(1, len(centerline_mm)):
    arc_length += np.linalg.norm(centerline_mm[i] - centerline_mm[i-1])

# Tortuosity Index
tortuosity_index = ((arc_length - chord_length) / chord_length) * 100.0

# Classification
if tortuosity_index < 10:
    classification = "Normal"
elif tortuosity_index < 20:
    classification = "Mild Tortuosity"
elif tortuosity_index < 35:
    classification = "Moderate Tortuosity"
else:
    classification = "Severe Tortuosity"

print(f"Ground Truth:")
print(f"  Chord Length: {chord_length:.2f} mm")
print(f"  Arc Length: {arc_length:.2f} mm")
print(f"  Tortuosity Index: {tortuosity_index:.2f}%")
print(f"  Classification: {classification}")

# Create the aorta in CT volume
label_data = np.zeros((nx, ny, nz), dtype=np.int16)

for i in range(len(z_values)):
    z = int(z_values[i])
    cx = centerline_x[i]
    cy = centerline_y[i]
    
    if 0 <= z < nz:
        # Create circular cross-section at this level
        for dx in range(-20, 21):
            for dy in range(-20, 21):
                x = int(cx + dx)
                y = int(cy + dy)
                if 0 <= x < nx and 0 <= y < ny:
                    dist = np.sqrt(dx**2 + dy**2)
                    if dist <= aorta_radius_voxels:
                        # Inside aorta - contrast enhanced blood
                        ct_data[x, y, z] = int(np.random.normal(180, 25))
                        label_data[x, y, z] = 10  # Aorta label

# Add some fat layers for realism
fat_inner = ((X - center_x)**2 / (88**2) + (Y - center_y)**2 / (68**2)) <= 1.0
fat_outer = ((X - center_x)**2 / (95**2) + (Y - center_y)**2 / (75**2)) <= 1.0
fat_ring = fat_outer & ~fat_inner

for z in range(nz):
    fat_mask = fat_ring & body_mask & (label_data[:, :, z] == 0)
    ct_data[:, :, z][fat_mask] = np.random.normal(-80, 15, (np.sum(fat_mask),)).astype(np.int16)

# Save CT volume
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
nib.save(ct_img, ct_path)
print(f"\nCT volume saved: {ct_path}")
print(f"  Shape: {ct_data.shape}")
print(f"  Spacing: {spacing} mm")

# Save label map (hidden from agent)
label_img = nib.Nifti1Image(label_data, affine)
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
nib.save(label_img, label_path)
print(f"Label map saved: {label_path}")

# Save ground truth measurements
gt_data = {
    "case_id": case_id,
    "chord_length_mm": float(chord_length),
    "arc_length_mm": float(arc_length),
    "tortuosity_index_percent": float(tortuosity_index),
    "classification": classification,
    "centerline_points_count": len(centerline_mm),
    "centerline_points_mm": centerline_mm.tolist(),
    "aorta_superior_z_mm": float(z_start * spacing[2]),
    "aorta_inferior_z_mm": float(z_end * spacing[2]),
    "voxel_spacing_mm": list(spacing),
    "sinusoid_amplitude_mm": float(amplitude_voxels * spacing[0]),
    "sinusoid_frequency": float(frequency)
}

gt_path = os.path.join(gt_dir, f"{case_id}_tortuosity_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved: {gt_path}")

# Save case ID for other scripts
with open("/tmp/tortuosity_case_id", "w") as f:
    f.write(case_id)

print("\n=== Data generation complete ===")
PYEOF

# Get the case ID used
if [ -f /tmp/tortuosity_case_id ]; then
    CASE_ID=$(cat /tmp/tortuosity_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Verify files exist
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume created: $CT_FILE"

if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_tortuosity_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Create Slicer Python script to load CT
cat > /tmp/load_tortuosity_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading CT scan for tortuosity assessment: {case_id}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT_Tortuous")
    
    # Set abdominal soft tissue window
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on the middle of the data (where aorta is visible)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2
    
    # Set Red slice (axial) to show aorta cross-section
    redSliceNode = slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode()
    redSliceNode.SetSliceOffset(center_z)
    
    print(f"CT loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Centered on z={center_z:.1f} mm")
else:
    print("ERROR: Could not load CT volume")

print("\\nSetup complete - ready for tortuosity assessment")
print("\\nTIP: Navigate through axial slices to trace the aorta from diaphragm to bifurcation")
PYEOF

# Kill any existing Slicer
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
echo "Launching 3D Slicer with CT data..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_tortuosity_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to load
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
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/tortuosity_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Aortic Tortuosity Index Assessment"
echo "=========================================="
echo ""
echo "You are given an abdominal CT of an elderly patient with hypertension."
echo "Aortic tortuosity is a marker of vascular aging and cardiovascular risk."
echo ""
echo "Your goal:"
echo "  1. Identify the abdominal aorta from diaphragm (T12) to bifurcation (L4)"
echo "  2. Place fiducial points along the aortic centerline (minimum 8-10 points)"
echo "  3. Calculate:"
echo "     - Chord Length: straight-line distance first to last point (mm)"
echo "     - Arc Length: sum of distances between consecutive points (mm)"
echo "     - Tortuosity Index: ((Arc - Chord) / Chord) × 100%"
echo "  4. Classify:"
echo "     - Normal: TI < 10%"
echo "     - Mild Tortuosity: TI 10-20%"
echo "     - Moderate Tortuosity: TI 20-35%"
echo "     - Severe Tortuosity: TI > 35%"
echo ""
echo "Save your outputs:"
echo "  - Centerline: ~/Documents/SlicerData/AMOS/aorta_centerline.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/tortuosity_report.json"
echo ""