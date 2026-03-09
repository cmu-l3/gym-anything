#!/bin/bash
echo "=== Setting up Duodenal Diameter Assessment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define directories
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_duodenum_001"

# Ensure directories exist
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Clean any previous task artifacts
rm -f "$AMOS_DIR/duodenal_measurement.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/duodenal_report.json" 2>/dev/null || true
rm -f /tmp/duodenal_task_result.json 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "measurement_exists": false,
    "report_exists": false,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Preparing abdominal CT data with duodenum..."

# Generate synthetic abdominal CT with realistic duodenum
python3 << 'PYEOF'
import os
import json
import numpy as np

# Ensure dependencies
try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    from scipy.ndimage import binary_dilation, gaussian_filter
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import binary_dilation, gaussian_filter

case_id = "amos_duodenum_001"
amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"

np.random.seed(42)

# Volume dimensions (256 x 256 x 120 axial slices)
nx, ny, nz = 256, 256, 120
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel

# Affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize CT volume with soft tissue background
ct_data = np.random.normal(40, 15, (nx, ny, nz)).astype(np.float32)

# Create body outline (elliptical)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2
body_mask = ((X - center_x)**2 / (105**2) + (Y - center_y)**2 / (85**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (vertebral body)
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 18**2
    ct_data[:, :, z][spine_mask] = np.random.normal(450, 60, np.sum(spine_mask))

# Create aorta (anterior to spine)
aorta_cx, aorta_cy = center_x, center_y + 30
aorta_radius = 12
for z in range(nz):
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= aorta_radius**2
    ct_data[:, :, z][aorta_mask & body_mask] = np.random.normal(180, 25, np.sum(aorta_mask & body_mask))

# Create liver (right upper quadrant)
liver_cx, liver_cy = center_x - 40, center_y - 20
for z in range(25, 85):
    liver_mask = ((X - liver_cx)**2 / (50**2) + (Y - liver_cy)**2 / (40**2)) <= 1.0
    ct_data[:, :, z][liver_mask & body_mask] = np.random.normal(60, 12, np.sum(liver_mask & body_mask))

# Initialize label map
label_data = np.zeros((nx, ny, nz), dtype=np.int16)

# ============================================================
# Create DUODENUM (C-loop around pancreatic head)
# ============================================================
# Randomly decide if duodenum is dilated (for clinical variety)
is_dilated = np.random.random() > 0.5  # 50% chance of dilation
dilation_severity = np.random.choice(['mild', 'moderate', 'severe']) if is_dilated else 'none'

# Base duodenal radius (internal lumen)
if dilation_severity == 'none':
    base_radius_mm = np.random.uniform(10, 14)  # Normal: 20-28mm diameter
elif dilation_severity == 'mild':
    base_radius_mm = np.random.uniform(16, 19)  # Mild: 32-38mm
elif dilation_severity == 'moderate':
    base_radius_mm = np.random.uniform(21, 24)  # Moderate: 42-48mm
else:
    base_radius_mm = np.random.uniform(27, 32)  # Severe: 54-64mm

base_radius_voxels = base_radius_mm / spacing[0]

# Track max diameter and location
max_diameter_mm = 0
max_location = "D3"
max_slice_idx = 60

# D1: Duodenal bulb (z = 70-78, transition from stomach)
d1_z_range = range(70, 78)
d1_cx, d1_cy = center_x - 50, center_y - 30

for z in d1_z_range:
    radius = base_radius_voxels * np.random.uniform(0.9, 1.1)
    duod_mask = ((X - d1_cx)**2 + (Y - d1_cy)**2) <= radius**2
    ct_data[:, :, z][duod_mask & body_mask] = np.random.normal(30, 12, np.sum(duod_mask & body_mask))
    label_data[:, :, z][duod_mask & body_mask] = 14  # Duodenum label
    
    diameter = 2 * radius * spacing[0]
    if diameter > max_diameter_mm:
        max_diameter_mm = diameter
        max_location = "D1"
        max_slice_idx = z

# D2: Descending duodenum (z = 55-70, vertical along pancreatic head)
d2_z_range = range(55, 70)

for z in d2_z_range:
    z_fraction = (z - 55) / 15.0
    d2_cx = center_x - 45 + int(5 * z_fraction)
    d2_cy = center_y + int(-25 + 30 * z_fraction)
    
    radius = base_radius_voxels * np.random.uniform(0.95, 1.05)
    duod_mask = ((X - d2_cx)**2 + (Y - d2_cy)**2) <= radius**2
    ct_data[:, :, z][duod_mask & body_mask] = np.random.normal(30, 12, np.sum(duod_mask & body_mask))
    label_data[:, :, z][duod_mask & body_mask] = 14
    
    diameter = 2 * radius * spacing[0]
    if diameter > max_diameter_mm:
        max_diameter_mm = diameter
        max_location = "D2"
        max_slice_idx = z

# D3: Horizontal duodenum (z = 45-55, crosses midline - often widest)
d3_z_range = range(45, 55)
d3_dilation_factor = 1.15 if is_dilated else 1.0

for z in d3_z_range:
    z_fraction = (z - 45) / 10.0
    d3_cx = center_x - 35 + int(70 * z_fraction)
    d3_cy = center_y + 8
    
    radius = base_radius_voxels * d3_dilation_factor * np.random.uniform(0.95, 1.08)
    duod_mask = ((X - d3_cx)**2 + (Y - d3_cy)**2) <= radius**2
    ct_data[:, :, z][duod_mask & body_mask] = np.random.normal(30, 12, np.sum(duod_mask & body_mask))
    label_data[:, :, z][duod_mask & body_mask] = 14
    
    diameter = 2 * radius * spacing[0]
    if diameter > max_diameter_mm:
        max_diameter_mm = diameter
        max_location = "D3"
        max_slice_idx = z

# D4: Ascending duodenum (z = 38-45, rises to DJ junction)
d4_z_range = range(38, 45)

for z in d4_z_range:
    z_fraction = (z - 38) / 7.0
    d4_cx = center_x + 35 - int(10 * z_fraction)
    d4_cy = center_y - int(5 * z_fraction)
    
    radius = base_radius_voxels * np.random.uniform(0.85, 0.95)
    duod_mask = ((X - d4_cx)**2 + (Y - d4_cy)**2) <= radius**2
    ct_data[:, :, z][duod_mask & body_mask] = np.random.normal(30, 12, np.sum(duod_mask & body_mask))
    label_data[:, :, z][duod_mask & body_mask] = 14
    
    diameter = 2 * radius * spacing[0]
    if diameter > max_diameter_mm:
        max_diameter_mm = diameter
        max_location = "D4"
        max_slice_idx = z

# Add wall enhancement to duodenum
duod_full_mask = (label_data == 14)
duod_dilated = binary_dilation(duod_full_mask, iterations=2)
duod_wall = duod_dilated & ~duod_full_mask
ct_data[duod_wall] = np.random.normal(50, 10, np.sum(duod_wall))

# Add stomach for context (proximal to D1)
stomach_cx, stomach_cy = center_x - 30, center_y - 45
for z in range(60, 90):
    stomach_mask = ((X - stomach_cx)**2 / (35**2) + (Y - stomach_cy)**2 / (25**2)) <= 1.0
    ct_data[:, :, z][stomach_mask & body_mask] = np.random.normal(25, 15, np.sum(stomach_mask & body_mask))
    label_data[:, :, z][stomach_mask & body_mask] = 7  # Stomach label

# Smooth the CT data for realism
ct_data = gaussian_filter(ct_data.astype(np.float32), sigma=0.5)
ct_data = np.clip(ct_data, -1024, 3071).astype(np.int16)

# Save NIfTI files
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path}")

label_img = nib.Nifti1Image(label_data, affine)
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
nib.save(label_img, label_path)
print(f"Label map saved: {label_path}")

# Classification based on max diameter
if max_diameter_mm <= 30:
    classification = "Normal"
elif max_diameter_mm <= 40:
    classification = "Mildly dilated"
elif max_diameter_mm <= 50:
    classification = "Moderately dilated"
else:
    classification = "Severely dilated"

# Create ground truth JSON
ground_truth = {
    "case_id": case_id,
    "max_diameter_mm": float(round(max_diameter_mm, 1)),
    "location": max_location,
    "slice_index": int(max_slice_idx),
    "classification": classification,
    "is_dilated": is_dilated,
    "dilation_severity": dilation_severity,
    "spacing_mm": [float(s) for s in spacing],
    "volume_shape": [nx, ny, nz],
    "tolerance_mm": 5.0,
    "anatomical_notes": {
        "D1_z_range": [70, 78],
        "D2_z_range": [55, 70],
        "D3_z_range": [45, 55],
        "D4_z_range": [38, 45]
    }
}

gt_path = os.path.join(gt_dir, f"{case_id}_duodenum_gt.json")
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"\nGround truth saved: {gt_path}")
print(f"  Max diameter: {max_diameter_mm:.1f} mm")
print(f"  Location: {max_location}")
print(f"  Slice: {max_slice_idx}")
print(f"  Classification: {classification}")
PYEOF

# Save case ID
echo "$CASE_ID" > /tmp/amos_case_id

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume created: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_duodenum_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT data
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
sleep 5
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null && DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for full startup
sleep 10

# Maximize and focus Slicer window
echo "Configuring Slicer window..."
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Duodenal Loop Diameter Assessment"
echo "========================================"
echo ""
echo "You are given an abdominal CT scan. The patient is being evaluated"
echo "for possible small bowel obstruction."
echo ""
echo "Your goal:"
echo "  1. Identify the duodenum (C-shaped loop around pancreatic head)"
echo "  2. Find the widest segment (D1, D2, D3, or D4)"
echo "  3. Measure the maximum internal diameter (mm) using ruler tool"
echo "  4. Classify: Normal (≤30mm), Mildly (31-40mm), Moderately (41-50mm), Severely (>50mm)"
echo ""
echo "Save your outputs:"
echo "  - Measurement: ~/Documents/SlicerData/AMOS/duodenal_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/duodenal_report.json"
echo ""