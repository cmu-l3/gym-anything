#!/bin/bash
# Prepare abdominal CT data for aorta measurement task
#
# Approach: Try to download a single case from AMOS 2022 dataset.
# If download fails or times out, generate synthetic abdominal CT data
# with a known aorta structure for reliable testing.
#
# The synthetic data has realistic properties:
# - Abdominal CT Hounsfield units (soft tissue ~40 HU, aorta ~150 HU, bone ~400 HU)
# - Realistic voxel spacing (0.75mm x 0.75mm x 2.5mm)
# - Cylindrical aorta with known diameter for ground truth verification
# - Label map with aorta segmentation (label 10)

set -e

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
DOWNLOAD_DIR="/tmp/amos_download"
CASE_ID="${1:-amos_0001}"

echo "=== Preparing Abdominal CT Data for Aorta Measurement ==="
echo "Data directory: $AMOS_DIR"
echo "Case ID: $CASE_ID"

mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$DOWNLOAD_DIR"

# Check if data already exists
if [ -f "$AMOS_DIR/${CASE_ID}.nii.gz" ] && [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" ]; then
    echo "Data already exists for $CASE_ID"
    echo "$CASE_ID" > /tmp/amos_case_id
    exit 0
fi

# ============================================================
# Ensure Python dependencies
# ============================================================
echo "Ensuring Python dependencies..."
pip install -q numpy nibabel 2>/dev/null || pip3 install -q numpy nibabel 2>/dev/null || true

# ============================================================
# Try to download real AMOS data (with short timeout)
# ============================================================
DOWNLOAD_SUCCESS=false

echo "Attempting to download real AMOS case (timeout: 300s)..."

# AMOS is a single 11GB zip - try with a strict timeout
# If it fails, we'll fall back to synthetic data
AMOS_ZIP="$DOWNLOAD_DIR/amos22.zip"

timeout 300 curl -L -f -o "$AMOS_ZIP" \
    "https://zenodo.org/records/7155725/files/amos22.zip" 2>/dev/null && \
    DOWNLOAD_SUCCESS=true || DOWNLOAD_SUCCESS=false

if [ "$DOWNLOAD_SUCCESS" = true ] && [ -f "$AMOS_ZIP" ] && [ "$(stat -c%s "$AMOS_ZIP" 2>/dev/null || echo 0)" -gt 100000000 ]; then
    echo "Download successful. Extracting case $CASE_ID..."
    cd "$DOWNLOAD_DIR"
    unzip -o -q "$AMOS_ZIP" "amos22/imagesTr/${CASE_ID}.nii.gz" -d "$DOWNLOAD_DIR/" 2>/dev/null || true
    unzip -o -q "$AMOS_ZIP" "amos22/labelsTr/${CASE_ID}.nii.gz" -d "$DOWNLOAD_DIR/" 2>/dev/null || true

    IMAGE_FILE=""
    LABEL_FILE=""
    for search_dir in "$DOWNLOAD_DIR/amos22" "$DOWNLOAD_DIR"; do
        [ -f "$search_dir/imagesTr/${CASE_ID}.nii.gz" ] && IMAGE_FILE="$search_dir/imagesTr/${CASE_ID}.nii.gz"
        [ -f "$search_dir/labelsTr/${CASE_ID}.nii.gz" ] && LABEL_FILE="$search_dir/labelsTr/${CASE_ID}.nii.gz"
    done

    if [ -n "$IMAGE_FILE" ] && [ -n "$LABEL_FILE" ]; then
        cp "$IMAGE_FILE" "$AMOS_DIR/${CASE_ID}.nii.gz"
        cp "$LABEL_FILE" "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"
        DOWNLOAD_SUCCESS=true
        echo "Real AMOS data extracted successfully"
    else
        DOWNLOAD_SUCCESS=false
        echo "Could not extract case from zip"
    fi
    rm -f "$AMOS_ZIP" 2>/dev/null || true
else
    echo "Download failed or timed out. Using synthetic data."
    rm -f "$AMOS_ZIP" 2>/dev/null || true
    DOWNLOAD_SUCCESS=false
fi

# ============================================================
# Generate synthetic data if download failed
# ============================================================
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "Generating synthetic abdominal CT with aorta..."

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

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

np.random.seed(42)

# Realistic abdominal CT parameters
# Shape: ~512 x 512 x 200 slices
# Use smaller dimensions for speed: 256 x 256 x 100
nx, ny, nz = 256, 256, 100
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel (typical abdominal CT)

# Create affine matrix
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# ============================================================
# Generate CT volume with realistic HU values
# ============================================================
# Background air: -1000 HU
# Soft tissue: 20-60 HU
# Aorta (contrast): 150-300 HU
# Bone/spine: 300-800 HU
# Fat: -100 to -50 HU

ct_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Fill with soft tissue background (with noise)
ct_data[:] = np.random.normal(40, 15, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2
body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (80**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (vertebral body - bright bone)
spine_cx, spine_cy = center_x, center_y + 50  # Posterior
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 15**2
    ct_data[:, :, z][spine_mask] = np.random.normal(500, 80, (np.sum(spine_mask),)).astype(np.int16)

# Create aorta - cylindrical vessel anterior to spine
# Aorta diameter varies: normal ~20mm, we'll make it 26mm (borderline)
aorta_cx, aorta_cy = center_x, center_y + 25  # Anterior to spine
aorta_radius_voxels = 26 / 2.0 / spacing[0]  # ~16.7 voxels for 26mm diameter

# Make the aorta slightly larger at one level (to simulate ectasia)
# Max diameter at slice 45: 33mm (ectatic)
max_diam_mm = 33.0  # Ectatic range
max_diam_slice = 45

for z in range(nz):
    # Vary diameter along z
    # Gaussian-like profile with peak at max_diam_slice
    diam_factor = 1.0 + 0.27 * np.exp(-((z - max_diam_slice)**2) / (2 * 15**2))
    current_radius = aorta_radius_voxels * diam_factor

    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= current_radius**2
    # Aorta with contrast enhancement
    ct_data[:, :, z][aorta_mask & body_mask] = np.random.normal(
        200, 30, (np.sum(aorta_mask & body_mask),)).astype(np.int16)

# Add some fat layers
fat_inner = ((X - center_x)**2 / (90**2) + (Y - center_y)**2 / (70**2)) <= 1.0
fat_outer = ((X - center_x)**2 / (95**2) + (Y - center_y)**2 / (75**2)) <= 1.0
fat_ring = fat_outer & ~fat_inner
for z in range(nz):
    ct_data[:, :, z][fat_ring & body_mask] = np.random.normal(-80, 15, (np.sum(fat_ring & body_mask),)).astype(np.int16)

# ============================================================
# Generate label map
# ============================================================
# Only label the aorta (label 10, matching AMOS convention)
label_data = np.zeros((nx, ny, nz), dtype=np.int16)

for z in range(nz):
    diam_factor = 1.0 + 0.27 * np.exp(-((z - max_diam_slice)**2) / (2 * 15**2))
    current_radius = aorta_radius_voxels * diam_factor
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= current_radius**2
    label_data[:, :, z][aorta_mask & body_mask] = 10  # Aorta label

# Also add a few other labels for realism
# Label 6: liver (right side, anterior)
liver_cx, liver_cy = center_x - 30, center_y - 10
for z in range(20, 80):
    liver_mask = ((X - liver_cx)**2 / (40**2) + (Y - liver_cy)**2 / (35**2)) <= 1.0
    aorta_mask_z = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= (aorta_radius_voxels * 1.5)**2
    label_data[:, :, z][liver_mask & body_mask & ~aorta_mask_z] = 6

# Label 1: spleen (left side)
spleen_cx, spleen_cy = center_x + 50, center_y + 10
for z in range(30, 65):
    spleen_mask = ((X - spleen_cx)**2 + (Y - spleen_cy)**2) <= 20**2
    label_data[:, :, z][spleen_mask & body_mask] = 1

# ============================================================
# Save NIfTI files
# ============================================================
ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path} (shape: {ct_data.shape})")

label_img = nib.Nifti1Image(label_data, affine)
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
nib.save(label_img, label_path)
print(f"Label map saved: {label_path}")

# ============================================================
# Compute ground truth measurements
# ============================================================
aorta = (label_data == 10)

max_diameter = 0
max_slice_idx = 0
max_slice_center = [0, 0, 0]

for z in range(nz):
    slice_mask = aorta[:, :, z]
    if not np.any(slice_mask):
        continue

    # Area-equivalent diameter
    area_pixels = np.sum(slice_mask)
    area_mm2 = area_pixels * spacing[0] * spacing[1]
    equiv_diameter = 2 * np.sqrt(area_mm2 / np.pi)

    if equiv_diameter > max_diameter:
        max_diameter = equiv_diameter
        max_slice_idx = z
        rows = np.any(slice_mask, axis=1)
        cols = np.any(slice_mask, axis=0)
        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]
        max_slice_center = [
            float((rmin + rmax) / 2.0 * spacing[0]),
            float((cmin + cmax) / 2.0 * spacing[1]),
            float(z * spacing[2])
        ]

# Clinical classification
if max_diameter < 30:
    classification = "Normal"
elif max_diameter < 35:
    classification = "Ectatic"
else:
    classification = "Aneurysmal"

# Approximate vertebral level
total_z = nz * spacing[2]
slice_z_mm = max_slice_idx * spacing[2]
z_fraction = slice_z_mm / total_z if total_z > 0 else 0.5
if z_fraction < 0.2:
    vertebral_level = "L4"
elif z_fraction < 0.4:
    vertebral_level = "L3"
elif z_fraction < 0.6:
    vertebral_level = "L2"
elif z_fraction < 0.8:
    vertebral_level = "L1"
else:
    vertebral_level = "T12"

gt_data = {
    "case_id": case_id,
    "aorta_label": 10,
    "max_diameter_mm": float(round(max_diameter, 2)),
    "max_slice_index": int(max_slice_idx),
    "max_slice_center_mm": max_slice_center,
    "classification": classification,
    "approximate_vertebral_level": vertebral_level,
    "ct_shape": list(ct_data.shape),
    "voxel_spacing_mm": list(spacing),
    "total_aorta_voxels": int(np.sum(aorta)),
    "aorta_extent_slices": int(np.sum(np.any(aorta, axis=(0, 1)))),
    "synthetic": True,
}

gt_path = os.path.join(gt_dir, f"{case_id}_aorta_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved: {gt_path}")
print(f"  Max aorta diameter: {gt_data['max_diameter_mm']:.1f} mm")
print(f"  At slice: {gt_data['max_slice_index']}")
print(f"  Classification: {gt_data['classification']}")
print(f"  Level: {gt_data['approximate_vertebral_level']}")
PYEOF

fi

# ============================================================
# If we downloaded real data, compute ground truth from labels
# ============================================================
if [ "$DOWNLOAD_SUCCESS" = true ] && [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" ] && [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" ]; then
    echo "Computing ground truth from real AMOS labels..."

    export CASE_ID GROUND_TRUTH_DIR
    python3 << 'PYEOF'
import os, sys, json
import numpy as np
import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

seg = nib.load(label_path)
data = seg.get_fdata().astype(np.int32)
spacing = seg.header.get_zooms()[:3]

# Find aorta label (8 or 10)
aorta_label = None
for candidate in [8, 10]:
    if np.sum(data == candidate) > 100:
        aorta_label = candidate
        break

if aorta_label is None:
    print("ERROR: No aorta found")
    sys.exit(1)

aorta = (data == aorta_label)

max_diameter = 0
max_slice_idx = 0
max_slice_center = [0, 0, 0]

for z in range(aorta.shape[2]):
    sl = aorta[:, :, z]
    if not np.any(sl):
        continue
    area = np.sum(sl) * float(spacing[0]) * float(spacing[1])
    diam = 2 * np.sqrt(area / np.pi)
    if diam > max_diameter:
        max_diameter = diam
        max_slice_idx = z
        rows = np.any(sl, axis=1)
        cols = np.any(sl, axis=0)
        r0, r1 = np.where(rows)[0][[0, -1]]
        c0, c1 = np.where(cols)[0][[0, -1]]
        max_slice_center = [float((r0+r1)/2*spacing[0]), float((c0+c1)/2*spacing[1]), float(z*spacing[2])]

classification = "Normal" if max_diameter < 30 else ("Ectatic" if max_diameter < 35 else "Aneurysmal")
total_z = aorta.shape[2] * float(spacing[2])
zf = max_slice_idx * float(spacing[2]) / total_z if total_z > 0 else 0.5
levels = [(0.2, "L4"), (0.4, "L3"), (0.6, "L2"), (0.8, "L1")]
vertebral_level = "T12"
for thresh, lvl in levels:
    if zf < thresh:
        vertebral_level = lvl
        break

gt_data = {
    "case_id": case_id, "aorta_label": int(aorta_label),
    "max_diameter_mm": float(round(max_diameter, 2)),
    "max_slice_index": int(max_slice_idx),
    "max_slice_center_mm": max_slice_center,
    "classification": classification,
    "approximate_vertebral_level": vertebral_level,
    "ct_shape": list(data.shape),
    "voxel_spacing_mm": [float(s) for s in spacing],
    "total_aorta_voxels": int(np.sum(aorta)),
    "aorta_extent_slices": int(np.sum(np.any(aorta, axis=(0, 1)))),
}

gt_path = os.path.join(gt_dir, f"{case_id}_aorta_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved: {gt_path}")
print(f"  Diameter: {gt_data['max_diameter_mm']:.1f} mm, Class: {gt_data['classification']}")
PYEOF
fi

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Save case ID
echo "$CASE_ID" > /tmp/amos_case_id

echo ""
echo "=== Abdominal CT Data Preparation Complete ==="
echo "Case ID: $CASE_ID"
echo "CT volume: $AMOS_DIR/${CASE_ID}.nii.gz"
