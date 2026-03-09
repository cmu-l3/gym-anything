#!/bin/bash
echo "=== Setting up Intracerebral Hemorrhage ABC/2 Volume Task ==="

source /workspace/scripts/task_utils.sh

ICH_DIR="/home/ga/Documents/SlicerData/ICH"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$ICH_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f "$ICH_DIR/agent_measurements.mrk.json" 2>/dev/null || true
rm -f "$ICH_DIR/hemorrhage_report.json" 2>/dev/null || true
rm -f /tmp/ich_task_result.json 2>/dev/null || true

echo "Generating head CT with intracerebral hemorrhage..."

# Generate synthetic head CT with hemorrhage using Python
python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Install nibabel if needed
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

np.random.seed(42)

ich_dir = "/home/ga/Documents/SlicerData/ICH"
gt_dir = "/var/lib/slicer/ground_truth"

# CT parameters - standard emergency head CT
nx, ny, nz = 512, 512, 40  # 40 slices at 5mm each = 200mm coverage
slice_thickness_mm = 5.0
pixel_spacing = (0.5, 0.5)  # 0.5mm in-plane resolution

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = pixel_spacing[0]
affine[1, 1] = pixel_spacing[1]
affine[2, 2] = slice_thickness_mm

# ============================================================
# Generate head CT volume with realistic HU values
# ============================================================
ct_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Background air: -1000 HU
ct_data[:] = -1000

# Create skull outline (elliptical head)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Outer skull boundary
skull_outer_a, skull_outer_b = 220, 180
skull_outer = ((X - center_x)**2 / skull_outer_a**2 + (Y - center_y)**2 / skull_outer_b**2) <= 1.0

# Inner skull boundary (brain cavity)
skull_inner_a, skull_inner_b = 200, 160
skull_inner = ((X - center_x)**2 / skull_inner_a**2 + (Y - center_y)**2 / skull_inner_b**2) <= 1.0

# Skull bone (~1000 HU)
skull_bone = skull_outer & ~skull_inner

for z in range(nz):
    # Skull varies slightly by slice (thinner at top)
    scale = 1.0 - 0.15 * abs(z - nz//2) / (nz//2)
    scaled_skull_outer = ((X - center_x)**2 / (skull_outer_a * scale)**2 + 
                          (Y - center_y)**2 / (skull_outer_b * scale)**2) <= 1.0
    scaled_skull_inner = ((X - center_x)**2 / (skull_inner_a * scale)**2 + 
                          (Y - center_y)**2 / (skull_inner_b * scale)**2) <= 1.0
    scaled_skull_bone = scaled_skull_outer & ~scaled_skull_inner
    ct_data[:, :, z][scaled_skull_bone] = np.random.normal(1000, 100, np.sum(scaled_skull_bone)).astype(np.int16)

# Brain parenchyma (~35 HU with some variation)
for z in range(nz):
    scale = 1.0 - 0.15 * abs(z - nz//2) / (nz//2)
    brain_mask = ((X - center_x)**2 / (skull_inner_a * scale)**2 + 
                  (Y - center_y)**2 / (skull_inner_b * scale)**2) <= 1.0
    ct_data[:, :, z][brain_mask] = np.random.normal(35, 5, np.sum(brain_mask)).astype(np.int16)

# Add ventricles (CSF ~ 5-10 HU)
vent_cx, vent_cy = center_x, center_y
for z in range(int(nz * 0.3), int(nz * 0.7)):
    # Lateral ventricles (simplified as two ellipses)
    z_factor = 1.0 - 0.5 * abs(z - nz//2) / (nz//2)
    for offset in [-40, 40]:  # Left and right ventricles
        vent_mask = ((X - (vent_cx + offset))**2 / (25 * z_factor)**2 + 
                     (Y - vent_cy)**2 / (15 * z_factor)**2) <= 1.0
        ct_data[:, :, z][vent_mask] = np.random.normal(8, 2, np.sum(vent_mask)).astype(np.int16)

# ============================================================
# Create hemorrhage with KNOWN ABC dimensions
# ============================================================
# Location: Right basal ganglia (common hypertensive hemorrhage site)
hem_cx = center_x + 50  # Right side
hem_cy = center_y - 20  # Slightly anterior
hem_cz = nz // 2  # Mid-level

# ABC/2 ground truth dimensions (designed to be ~35-40 mL)
# Volume = (A * B * C) / 2
# Target volume around 38 mL (above 30mL threshold)
A_cm = 4.8  # 48mm = largest axial diameter
B_cm = 3.6  # 36mm = perpendicular diameter
C_cm = 4.5  # 45mm = craniocaudal extent (9 slices × 5mm)

# Convert to voxels
A_voxels = A_cm * 10 / pixel_spacing[0]  # 96 voxels
B_voxels = B_cm * 10 / pixel_spacing[1]  # 72 voxels
C_slices = C_cm * 10 / slice_thickness_mm  # 9 slices

# Calculate expected volume
expected_volume_ml = (A_cm * B_cm * C_cm) / 2
print(f"Ground truth ABC/2 volume: {expected_volume_ml:.2f} mL")
print(f"A={A_cm}cm, B={B_cm}cm, C={C_cm}cm")

# Create ellipsoidal hemorrhage
hem_label = np.zeros((nx, ny, nz), dtype=np.uint8)
A_radius = A_voxels / 2
B_radius = B_voxels / 2
C_radius = C_slices / 2

for z in range(nz):
    z_dist = abs(z - hem_cz) / C_radius if C_radius > 0 else 999
    if z_dist > 1.0:
        continue
    
    # Ellipse cross-section at this z level
    # As we move away from center, the ellipse shrinks
    scale_z = np.sqrt(max(0, 1 - z_dist**2))
    curr_A = A_radius * scale_z
    curr_B = B_radius * scale_z
    
    if curr_A < 1 or curr_B < 1:
        continue
    
    for x in range(max(0, int(hem_cx - curr_A - 5)), min(nx, int(hem_cx + curr_A + 5))):
        for y in range(max(0, int(hem_cy - curr_B - 5)), min(ny, int(hem_cy + curr_B + 5))):
            x_dist = (x - hem_cx) / curr_A if curr_A > 0 else 999
            y_dist = (y - hem_cy) / curr_B if curr_B > 0 else 999
            
            if x_dist**2 + y_dist**2 <= 1.0:
                # Add slight irregularity to make it realistic
                if np.random.random() > 0.02:  # 98% fill for slight irregularity
                    hem_label[x, y, z] = 1
                    # Hemorrhage HU: 50-90 (acute blood)
                    ct_data[x, y, z] = np.random.randint(55, 85)

# Count actual hemorrhage voxels
total_hem_voxels = np.sum(hem_label > 0)
voxel_volume_mm3 = pixel_spacing[0] * pixel_spacing[1] * slice_thickness_mm
segmented_volume_ml = total_hem_voxels * voxel_volume_mm3 / 1000
print(f"Segmented hemorrhage volume: {segmented_volume_ml:.2f} mL")

# Calculate slice-by-slice info for ground truth
slices_with_hem = []
max_area_slice = -1
max_area_voxels = 0

for z in range(nz):
    slice_hem = hem_label[:, :, z]
    area_voxels = np.sum(slice_hem > 0)
    if area_voxels > 0:
        slices_with_hem.append({
            "slice_index": z,
            "area_voxels": int(area_voxels),
            "area_mm2": float(area_voxels * pixel_spacing[0] * pixel_spacing[1])
        })
        if area_voxels > max_area_voxels:
            max_area_voxels = area_voxels
            max_area_slice = z

# Calculate actual A and B from the max area slice
if max_area_slice >= 0:
    max_slice = hem_label[:, :, max_area_slice]
    rows = np.any(max_slice, axis=1)
    cols = np.any(max_slice, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    
    actual_A_voxels = rmax - rmin + 1
    actual_B_voxels = cmax - cmin + 1
    actual_A_cm = actual_A_voxels * pixel_spacing[0] / 10
    actual_B_cm = actual_B_voxels * pixel_spacing[1] / 10
    print(f"Actual max slice dimensions: A={actual_A_cm:.2f}cm, B={actual_B_cm:.2f}cm")

# Count C using the ABC/2 method (weighted slice counting)
weighted_slice_count = 0
for s in slices_with_hem:
    ratio = s["area_voxels"] / max_area_voxels
    if ratio > 0.75:
        weighted_slice_count += 1.0
    elif ratio > 0.25:
        weighted_slice_count += 0.5
    # < 25% = 0 contribution

actual_C_cm = weighted_slice_count * slice_thickness_mm / 10
recalc_volume = (actual_A_cm * actual_B_cm * actual_C_cm) / 2
print(f"Recalculated ABC/2: A={actual_A_cm:.2f}, B={actual_B_cm:.2f}, C={actual_C_cm:.2f}")
print(f"Recalculated volume: {recalc_volume:.2f} mL")

# Determine surgical threshold
exceeds_threshold = recalc_volume > 30.0
classification = "Surgical candidate (>30mL)" if exceeds_threshold else "Conservative management (<30mL)"

# ============================================================
# Save CT volume
# ============================================================
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(ich_dir, "head_ct.nii.gz")
nib.save(ct_img, ct_path)
print(f"\nCT volume saved: {ct_path}")
print(f"Shape: {ct_data.shape}, Spacing: {pixel_spacing + (slice_thickness_mm,)}")

# ============================================================
# Save ground truth (hidden from agent)
# ============================================================
# Save hemorrhage segmentation
hem_img = nib.Nifti1Image(hem_label.astype(np.int16), affine)
hem_path = os.path.join(gt_dir, "hemorrhage_seg.nii.gz")
nib.save(hem_img, hem_path)
print(f"Hemorrhage segmentation saved: {hem_path}")

# Save ground truth measurements
gt_data = {
    "designed_values": {
        "A_cm": A_cm,
        "B_cm": B_cm,
        "C_cm": C_cm,
        "volume_ml": expected_volume_ml
    },
    "actual_measurements": {
        "A_cm": round(actual_A_cm, 2),
        "B_cm": round(actual_B_cm, 2),
        "C_cm": round(actual_C_cm, 2),
        "weighted_slice_count": weighted_slice_count,
        "abc2_volume_ml": round(recalc_volume, 2)
    },
    "segmented_volume_ml": round(segmented_volume_ml, 2),
    "max_area_slice_index": max_area_slice,
    "max_area_voxels": int(max_area_voxels),
    "max_area_mm2": float(max_area_voxels * pixel_spacing[0] * pixel_spacing[1]),
    "total_slices_with_hemorrhage": len(slices_with_hem),
    "slices_info": slices_with_hem,
    "exceeds_30ml_threshold": exceeds_threshold,
    "clinical_classification": classification,
    "hemorrhage_location": {
        "center_voxels": [int(hem_cx), int(hem_cy), int(hem_cz)],
        "anatomical_location": "Right basal ganglia"
    },
    "ct_parameters": {
        "slice_thickness_mm": slice_thickness_mm,
        "pixel_spacing_mm": list(pixel_spacing),
        "dimensions": list(ct_data.shape)
    }
}

gt_path = os.path.join(gt_dir, "ich_ground_truth.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth JSON saved: {gt_path}")

print("\n=== Hemorrhage Generation Complete ===")
print(f"ABC/2 Volume: {recalc_volume:.2f} mL")
print(f"Surgical threshold (30mL): {'EXCEEDED' if exceeds_threshold else 'NOT exceeded'}")
PYEOF

# Verify CT file exists
CT_FILE="$ICH_DIR/head_ct.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not generated!"
    exit 1
fi
echo "CT volume verified: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/ich_ground_truth.json" ]; then
    echo "ERROR: Ground truth not generated!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Create a Slicer Python script to load the CT with proper window/level
cat > /tmp/load_ich_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/ICH/head_ct.nii.gz"

print("Loading emergency head CT scan...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("HeadCT_Emergency")
    
    # Set brain window for optimal hemorrhage visualization
    # Standard brain window: W=80, L=40
    # Hemorrhage appears bright (50-90 HU) on this window
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(80)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to approximate hemorrhage location (mid-brain level)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    mid_z = (bounds[4] + bounds[5]) / 2
    
    # Set slice positions
    redSliceNode = slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode()
    redSliceNode.SetSliceOffset(mid_z)
    
    print(f"CT loaded with brain window (W=80, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Hemorrhage appears as bright (white) region in brain parenchyma")
    print("")
    print("Ready for ABC/2 volume measurement")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with head CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_ich_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/ich_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Intracerebral Hemorrhage ABC/2 Volume Estimation"
echo "========================================================"
echo ""
echo "EMERGENCY: Patient with sudden severe headache and altered consciousness."
echo "Head CT shows intracerebral hemorrhage. Neurosurgery needs the volume."
echo ""
echo "Calculate volume using ABC/2 method:"
echo "  1. Find slice with LARGEST hemorrhage area"
echo "  2. Measure A = largest diameter on that slice (cm)"
echo "  3. Measure B = perpendicular diameter on same slice (cm)"
echo "  4. Count slices for C (weighted by area)"
echo "  5. Volume (mL) = (A × B × C) / 2"
echo ""
echo "CLINICAL DECISION:"
echo "  Volume > 30mL → Consider surgical evacuation"
echo "  Volume < 30mL → Conservative management"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/ICH/agent_measurements.mrk.json"
echo "  - ~/Documents/SlicerData/ICH/hemorrhage_report.json"
echo ""