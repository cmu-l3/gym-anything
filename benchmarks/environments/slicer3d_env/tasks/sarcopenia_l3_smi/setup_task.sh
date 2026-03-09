#!/bin/bash
echo "=== Setting up L3 Sarcopenia Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Create patient info file
echo "Creating patient info file..."
cat > "$AMOS_DIR/patient_info.txt" << 'EOF'
=== Patient Information for Sarcopenia Assessment ===

Patient ID: AMOS_SARCO_001
Age: 72 years
Sex: Male
Height: 1.68 m (168 cm)
Weight: 65 kg (current)

Clinical Context:
- Newly diagnosed colorectal cancer
- Pre-operative assessment for potential surgical resection
- Geriatrician requested sarcopenia screening to assess surgical risk

Task:
1. Identify the L3 vertebral level on axial CT
2. Segment all skeletal muscles at L3 using HU threshold (-29 to +150)
3. Calculate Skeletal Muscle Area (SMA) in cm²
4. Calculate SMI = SMA / height² = SMA / 2.8224
5. Classify as sarcopenic if SMI < 52.4 cm²/m² (male threshold)

Muscles to include at L3:
- Psoas major (bilateral)
- Erector spinae/paraspinal muscles (bilateral)
- Rectus abdominis (anterior midline)
- External oblique (lateral)
- Internal oblique (lateral)
- Transversus abdominis (deep lateral)
- Quadratus lumborum (lateral to psoas)

Expected outputs:
- Segmentation: ~/Documents/SlicerData/AMOS/l3_muscle_segmentation.nii.gz
- Report: ~/Documents/SlicerData/AMOS/sarcopenia_report.json

Sarcopenia Classification (Prado criteria):
- Male: SMI < 52.4 cm²/m² = SARCOPENIC
- Female: SMI < 38.5 cm²/m² = SARCOPENIC
EOF

chown ga:ga "$AMOS_DIR/patient_info.txt" 2>/dev/null || true

# Generate ground truth L3 muscle segmentation
echo "Generating ground truth muscle segmentation..."
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
    from scipy.ndimage import label as scipy_label, binary_fill_holes, binary_erosion
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import label as scipy_label, binary_fill_holes, binary_erosion

amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"

# Ensure ground truth directory exists
os.makedirs(gt_dir, exist_ok=True)

# Find the CT volume
case_id = open("/tmp/amos_case_id").read().strip() if os.path.exists("/tmp/amos_case_id") else "amos_0001"
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

if not os.path.exists(ct_path):
    print(f"ERROR: CT not found at {ct_path}")
    sys.exit(1)

print(f"Loading CT: {ct_path}")
ct_nii = nib.load(ct_path)
ct_data = ct_nii.get_fdata()
spacing = ct_nii.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# Load organ labels if available (to exclude from muscle)
organ_mask = None
if os.path.exists(labels_path):
    labels_nii = nib.load(labels_path)
    labels_data = labels_nii.get_fdata()
    # Create mask of all organs to exclude
    organ_mask = (labels_data > 0)
    print(f"Loaded organ labels, unique values: {np.unique(labels_data)}")

# Find L3 vertebral level
# L3 is typically at approximately 40-50% of the abdominal CT height
nz = ct_data.shape[2]

# Estimate L3 region (typically 35-55% from inferior)
l3_search_start = int(nz * 0.35)
l3_search_end = int(nz * 0.55)

best_l3_slice = None
best_muscle_score = 0

print(f"Searching for L3 in slices {l3_search_start} to {l3_search_end}")

# Create coordinate grids
nx, ny = ct_data.shape[0], ct_data.shape[1]
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

for z in range(l3_search_start, l3_search_end):
    slice_data = ct_data[:, :, z]
    
    # Threshold for muscle (-29 to 150 HU)
    muscle_mask = (slice_data >= -29) & (slice_data <= 150)
    
    # Create body mask (anything > -500 HU, fill holes)
    body_mask = slice_data > -500
    body_mask = binary_fill_holes(body_mask)
    
    # Muscle within body only
    muscle_mask = muscle_mask & body_mask
    
    # Exclude organs if available
    if organ_mask is not None:
        muscle_mask = muscle_mask & ~organ_mask[:, :, z]
    
    # Count muscle pixels
    muscle_count = np.sum(muscle_mask)
    
    # L3 level typically has substantial muscle area
    if muscle_count > best_muscle_score:
        best_muscle_score = muscle_count
        best_l3_slice = z

# Use the slice near the peak with good muscle visibility
l3_slice = best_l3_slice if best_l3_slice else int(nz * 0.45)
print(f"Identified L3 slice: {l3_slice}")

# Create ground truth muscle segmentation at L3
slice_data = ct_data[:, :, l3_slice]

# Muscle HU range
muscle_mask = (slice_data >= -29) & (slice_data <= 150)

# Body mask
body_mask = slice_data > -500
body_mask = binary_fill_holes(body_mask)

# Apply body constraint
muscle_mask = muscle_mask & body_mask

# Exclude organs
if organ_mask is not None:
    muscle_mask = muscle_mask & ~organ_mask[:, :, l3_slice]

# Remove small components (noise)
labeled, n_components = scipy_label(muscle_mask)
if n_components > 0:
    component_sizes = [np.sum(labeled == i) for i in range(1, n_components + 1)]
    # Keep only components larger than 100 pixels
    for i in range(1, n_components + 1):
        if component_sizes[i-1] < 100:
            muscle_mask[labeled == i] = 0

# Calculate SMA in cm²
pixel_area_mm2 = spacing[0] * spacing[1]
pixel_area_cm2 = pixel_area_mm2 / 100.0  # mm² to cm²
sma_cm2 = np.sum(muscle_mask) * pixel_area_cm2

# Calculate SMI (height = 1.68m)
height_m = 1.68
smi = sma_cm2 / (height_m ** 2)

# Sarcopenia classification (male threshold = 52.4)
sarcopenic = smi < 52.4
classification = "sarcopenic" if sarcopenic else "normal"

print(f"L3 Slice: {l3_slice}")
print(f"Skeletal Muscle Area: {sma_cm2:.2f} cm²")
print(f"SMI: {smi:.2f} cm²/m²")
print(f"Sarcopenia: {classification}")

# Create full volume with only L3 slice segmented
gt_segmentation = np.zeros(ct_data.shape, dtype=np.uint8)
gt_segmentation[:, :, l3_slice] = muscle_mask.astype(np.uint8)

# Save ground truth segmentation
gt_seg_nii = nib.Nifti1Image(gt_segmentation, ct_nii.affine, ct_nii.header)
gt_seg_path = os.path.join(gt_dir, f"{case_id}_l3_muscle_gt.nii.gz")
nib.save(gt_seg_nii, gt_seg_path)
print(f"Ground truth segmentation saved: {gt_seg_path}")

# Save ground truth metrics
gt_metrics = {
    "case_id": case_id,
    "l3_slice_index": int(l3_slice),
    "l3_z_position_mm": float(l3_slice * spacing[2]),
    "voxel_spacing_mm": [float(s) for s in spacing],
    "skeletal_muscle_area_cm2": float(round(sma_cm2, 2)),
    "patient_height_m": height_m,
    "patient_sex": "male",
    "smi_cm2_m2": float(round(smi, 2)),
    "sarcopenia_threshold_cm2_m2": 52.4,
    "sarcopenia_classification": classification,
    "muscle_pixel_count": int(np.sum(muscle_mask)),
    "acceptable_slice_range": [int(l3_slice - 2), int(l3_slice + 2)],
    "acceptable_sma_range_cm2": [float(round(sma_cm2 * 0.85, 2)), float(round(sma_cm2 * 1.15, 2))]
}

gt_metrics_path = os.path.join(gt_dir, f"{case_id}_sarcopenia_gt.json")
with open(gt_metrics_path, "w") as f:
    json.dump(gt_metrics, f, indent=2)
print(f"Ground truth metrics saved: {gt_metrics_path}")

# Also save to /tmp for easier access during verification
import shutil
shutil.copy(gt_metrics_path, "/tmp/sarcopenia_ground_truth.json")
shutil.copy(gt_seg_path, "/tmp/ground_truth_l3_muscle.nii.gz")
os.chmod("/tmp/sarcopenia_ground_truth.json", 0o644)
os.chmod("/tmp/ground_truth_l3_muscle.nii.gz", 0o644)
print("Ground truth copied to /tmp for verification")
PYEOF

# Clean up any previous agent outputs
rm -f "$AMOS_DIR/l3_muscle_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/sarcopenia_report.json" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "segmentation_exists": false,
    "report_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod 755 "$AMOS_DIR" 2>/dev/null || true

# Create a Slicer Python script to load the CT with proper window/level
cat > /tmp/load_amos_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading AMOS CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")

    # Set default abdominal window/level for muscle visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window optimized for muscle
        displayNode.SetWindow(400)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Center on data - start at approximate L3 level (middle of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            # Start at approximate L3 level (45% from bottom)
            z_range = bounds[5] - bounds[4]
            l3_estimate = bounds[4] + z_range * 0.45
            sliceNode.SetSliceOffset(l3_estimate)
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])

    print(f"CT loaded with soft tissue window (W=400, L=50)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for L3 sarcopenia assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_ct.py > /tmp/slicer_launch.log 2>&1 &

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

    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1

    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: L3 Skeletal Muscle Index Assessment"
echo "==========================================="
echo ""
echo "Patient: 72-year-old male, Height: 1.68 m"
echo "Clinical context: Pre-surgical sarcopenia screening"
echo ""
echo "Your goal:"
echo "  1. Identify the L3 vertebral level on axial CT"
echo "  2. Segment ALL skeletal muscles at L3 (HU: -29 to +150)"
echo "  3. Calculate Skeletal Muscle Area (SMA) in cm²"
echo "  4. Calculate SMI = SMA / 2.8224 (height² in m²)"
echo "  5. Classify: sarcopenic if SMI < 52.4 cm²/m²"
echo ""
echo "Muscles to include:"
echo "  - Psoas major, Erector spinae, Rectus abdominis"
echo "  - Obliques, Transversus abdominis, Quadratus lumborum"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/l3_muscle_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/AMOS/sarcopenia_report.json"
echo ""
echo "Patient info file: $AMOS_DIR/patient_info.txt"
echo ""