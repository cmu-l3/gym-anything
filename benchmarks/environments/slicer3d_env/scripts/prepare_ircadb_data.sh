#!/bin/bash
# Prepare liver CT data for liver surgical planning task
#
# Approach: Try to download from 3D-IRCADb dataset.
# If download fails or times out, generate synthetic abdominal CT data
# with known liver, tumor, and portal vein structures for reliable testing.
#
# The synthetic data has realistic properties:
# - Abdominal CT Hounsfield units (soft tissue ~40 HU, liver ~60 HU, tumor ~45 HU)
# - Realistic voxel spacing (0.78mm x 0.78mm x 2.5mm)
# - Liver with embedded tumors and nearby portal vein
# - Multi-label segmentation: 1=liver, 2=tumor, 3=portal vein
# - Ground truth JSON with volume, count, distance, and invasion info

set -e

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
DOWNLOAD_DIR="/tmp/ircadb_download"
PATIENT_NUM="${1:-5}"  # Default to patient 5 (has tumors + portal vein)

echo "=== Preparing Liver CT Data for Surgical Planning ==="
echo "Data directory: $IRCADB_DIR"
echo "Patient number: $PATIENT_NUM"

mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$DOWNLOAD_DIR"

# Check if data already exists
if [ -d "$IRCADB_DIR/patient_${PATIENT_NUM}" ] && \
   [ -f "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json" ] && \
   [ -f "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_seg.nii.gz" ]; then
    echo "IRCADb data already exists for patient $PATIENT_NUM"
    echo "$PATIENT_NUM" > /tmp/ircadb_patient_num
    exit 0
fi

# ============================================================
# Ensure Python dependencies
# ============================================================
echo "Ensuring Python dependencies..."
pip install -q numpy nibabel scipy 2>/dev/null || pip3 install -q numpy nibabel scipy 2>/dev/null || true

# ============================================================
# Try to download real IRCADb data (with timeout)
# ============================================================
DOWNLOAD_SUCCESS=false

echo "Attempting to download 3D-IRCADb patient $PATIENT_NUM (timeout: 120s per URL)..."

IRCADB_URL="https://cloud.ircad.fr/index.php/s/JN3z7EynBiWCfHs/download?path=%2F3Dircadb1.${PATIENT_NUM}&files=3Dircadb1.${PATIENT_NUM}.zip"
IRCADB_ALT_URL="https://www.ircad.fr/softwares/3Dircadb/3Dircadb1/3Dircadb1.${PATIENT_NUM}.zip"
PATIENT_ZIP="$DOWNLOAD_DIR/3Dircadb1.${PATIENT_NUM}.zip"

# Try primary URL with timeout
timeout 120 curl -L -f -o "$PATIENT_ZIP" "$IRCADB_URL" 2>/dev/null && \
    DOWNLOAD_SUCCESS=true || DOWNLOAD_SUCCESS=false

# Check if download succeeded (at least 1MB)
if [ "$DOWNLOAD_SUCCESS" = false ] || [ ! -f "$PATIENT_ZIP" ] || \
   [ "$(stat -c%s "$PATIENT_ZIP" 2>/dev/null || echo 0)" -lt 1000000 ]; then
    echo "Primary URL failed, trying alternative (timeout: 120s)..."
    rm -f "$PATIENT_ZIP" 2>/dev/null || true
    timeout 120 curl -L -f -o "$PATIENT_ZIP" "$IRCADB_ALT_URL" 2>/dev/null && \
        DOWNLOAD_SUCCESS=true || DOWNLOAD_SUCCESS=false
fi

# Validate download
if [ "$DOWNLOAD_SUCCESS" = true ] && [ -f "$PATIENT_ZIP" ] && \
   [ "$(stat -c%s "$PATIENT_ZIP" 2>/dev/null || echo 0)" -gt 1000000 ]; then
    echo "Download successful: $(du -h "$PATIENT_ZIP" | cut -f1)"
    echo "Extracting patient data..."

    TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
    mkdir -p "$TARGET_DIR"

    cd "$DOWNLOAD_DIR"
    unzip -o -q "$PATIENT_ZIP" 2>/dev/null || true

    EXTRACTED_DIR=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d -name "3Dircadb1.*" | head -1)
    if [ -z "$EXTRACTED_DIR" ]; then
        EXTRACTED_DIR=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d -name "3Dircadb*" | head -1)
    fi

    if [ -n "$EXTRACTED_DIR" ]; then
        # Extract PATIENT_DICOM
        if [ -f "$EXTRACTED_DIR/PATIENT_DICOM.zip" ]; then
            mkdir -p "$TARGET_DIR/PATIENT_DICOM"
            unzip -o -q "$EXTRACTED_DIR/PATIENT_DICOM.zip" -d "$TARGET_DIR/PATIENT_DICOM/" 2>/dev/null || true
        elif [ -d "$EXTRACTED_DIR/PATIENT_DICOM" ]; then
            cp -r "$EXTRACTED_DIR/PATIENT_DICOM" "$TARGET_DIR/"
        fi

        # Extract MASKS_DICOM
        if [ -f "$EXTRACTED_DIR/MASKS_DICOM.zip" ]; then
            mkdir -p "$TARGET_DIR/MASKS_DICOM"
            unzip -o -q "$EXTRACTED_DIR/MASKS_DICOM.zip" -d "$TARGET_DIR/MASKS_DICOM/" 2>/dev/null || true
        elif [ -d "$EXTRACTED_DIR/MASKS_DICOM" ]; then
            cp -r "$EXTRACTED_DIR/MASKS_DICOM" "$TARGET_DIR/"
        fi

        # Extract nested mask zips
        MASKS_DIR="$TARGET_DIR/MASKS_DICOM"
        if [ -d "$MASKS_DIR" ]; then
            for nested_zip in "$MASKS_DIR"/*.zip; do
                if [ -f "$nested_zip" ]; then
                    dirname=$(basename "$nested_zip" .zip)
                    mkdir -p "$MASKS_DIR/$dirname"
                    unzip -o -q "$nested_zip" -d "$MASKS_DIR/$dirname/" 2>/dev/null || true
                fi
            done
        fi

        DICOM_COUNT=$(find "$TARGET_DIR/PATIENT_DICOM" -type f 2>/dev/null | wc -l)
        if [ "$DICOM_COUNT" -gt 10 ]; then
            echo "Extracted $DICOM_COUNT DICOM files"
            DOWNLOAD_SUCCESS=true
        else
            echo "Too few DICOM files ($DICOM_COUNT), treating as failed download"
            DOWNLOAD_SUCCESS=false
        fi
    else
        echo "Could not find extracted directory"
        DOWNLOAD_SUCCESS=false
    fi

    rm -f "$PATIENT_ZIP" 2>/dev/null || true
else
    echo "Download failed or timed out. Will use synthetic data."
    rm -f "$PATIENT_ZIP" 2>/dev/null || true
    DOWNLOAD_SUCCESS=false
fi

# ============================================================
# Process real data if downloaded successfully
# ============================================================
if [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo "Processing real IRCADb data..."
    TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"

    export PATIENT_NUM TARGET_DIR GROUND_TRUTH_DIR
    python3 << 'PYEOF'
import os, sys, json, glob
import numpy as np

patient_num = os.environ.get("PATIENT_NUM", "5")
target_dir = os.environ.get("TARGET_DIR")
gt_dir = os.environ.get("GROUND_TRUTH_DIR")
masks_dir = os.path.join(target_dir, "MASKS_DICOM")
dicom_dir = os.path.join(target_dir, "PATIENT_DICOM")

import nibabel as nib
import pydicom

def load_dicom_series(dicom_folder):
    dcm_files = []
    for root, dirs, files in os.walk(dicom_folder):
        for f in files:
            fpath = os.path.join(root, f)
            try:
                ds = pydicom.dcmread(fpath, force=True)
                if hasattr(ds, 'pixel_array'):
                    dcm_files.append((fpath, ds))
            except Exception:
                continue
    if not dcm_files:
        return None, None, None
    def get_sort_key(item):
        ds = item[1]
        if hasattr(ds, 'InstanceNumber') and ds.InstanceNumber is not None:
            return int(ds.InstanceNumber)
        if hasattr(ds, 'SliceLocation') and ds.SliceLocation is not None:
            return float(ds.SliceLocation)
        return 0
    dcm_files.sort(key=get_sort_key)
    slices = [ds.pixel_array for _, ds in dcm_files]
    volume = np.stack(slices, axis=-1)
    ds0 = dcm_files[0][1]
    pixel_spacing = list(ds0.PixelSpacing) if hasattr(ds0, 'PixelSpacing') else [1.0, 1.0]
    slice_thickness = float(ds0.SliceThickness) if hasattr(ds0, 'SliceThickness') else 1.0
    spacing = (float(pixel_spacing[0]), float(pixel_spacing[1]), slice_thickness)
    affine = np.eye(4)
    affine[0, 0] = spacing[0]
    affine[1, 1] = spacing[1]
    affine[2, 2] = spacing[2]
    return volume, spacing, affine

print(f"Loading patient CT from {dicom_dir}...")
ct_volume, ct_spacing, ct_affine = load_dicom_series(dicom_dir)
if ct_volume is None:
    print("ERROR: Could not load patient CT DICOM")
    sys.exit(1)
print(f"CT volume shape: {ct_volume.shape}, spacing: {ct_spacing}")

mask_types = {
    'liver': ['liver'],
    'tumor': ['livertumor', 'livertumor1', 'livertumor2', 'livertumor3', 'tumors'],
    'portal_vein': ['portalvein', 'venoussystem', 'venacava'],
}

loaded_masks = {}
for mask_name, possible_dirs in mask_types.items():
    for dirname in possible_dirs:
        mask_path = os.path.join(masks_dir, dirname)
        if os.path.isdir(mask_path) and len(os.listdir(mask_path)) > 0:
            mask_vol, _, _ = load_dicom_series(mask_path)
            if mask_vol is not None:
                binary_mask = (mask_vol > 0).astype(np.uint8)
                if mask_name == 'tumor':
                    if 'tumor' not in loaded_masks:
                        loaded_masks['tumor'] = binary_mask
                    else:
                        loaded_masks['tumor'] = np.maximum(loaded_masks['tumor'], binary_mask)
                else:
                    loaded_masks[mask_name] = binary_mask
                print(f"  {mask_name}: {np.sum(binary_mask > 0)} voxels")

gt_labelmap = np.zeros(ct_volume.shape, dtype=np.int16)
for mask_name, label in [('liver', 1), ('tumor', 2), ('portal_vein', 3)]:
    if mask_name in loaded_masks:
        mask = loaded_masks[mask_name]
        if mask.shape == ct_volume.shape:
            gt_labelmap[mask > 0] = label
        else:
            min_shape = tuple(min(a, b) for a, b in zip(mask.shape, ct_volume.shape))
            gt_labelmap[:min_shape[0], :min_shape[1], :min_shape[2]][
                mask[:min_shape[0], :min_shape[1], :min_shape[2]] > 0] = label

gt_nii = nib.Nifti1Image(gt_labelmap, ct_affine)
gt_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
nib.save(gt_nii, gt_path)
print(f"Ground truth segmentation saved to {gt_path}")

from scipy.ndimage import distance_transform_edt, label as scipy_label

voxel_volume_mm3 = float(np.prod(ct_spacing))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

liver_mask = (gt_labelmap == 1) | (gt_labelmap == 2)
tumor_mask = (gt_labelmap == 2)
portal_mask = (gt_labelmap == 3)

tumor_labeled, tumor_count = scipy_label(tumor_mask)

min_distance = float('inf')
if np.any(tumor_mask) and np.any(portal_mask):
    portal_dt = distance_transform_edt(~portal_mask, sampling=ct_spacing)
    min_distance = float(portal_dt[tumor_mask].min())

vascular_invasion = min_distance < 1.0

stats = {
    "patient_num": int(patient_num),
    "ct_shape": list(ct_volume.shape),
    "voxel_spacing_mm": list(ct_spacing),
    "voxel_volume_mm3": voxel_volume_mm3,
    "liver_volume_ml": float(np.sum(liver_mask) * voxel_volume_ml),
    "tumor_volume_ml": float(np.sum(tumor_mask) * voxel_volume_ml),
    "tumor_count": int(tumor_count),
    "portal_vein_voxels": int(np.sum(portal_mask)),
    "min_tumor_portal_distance_mm": float(min_distance) if not np.isinf(min_distance) else -1.0,
    "vascular_invasion": bool(vascular_invasion),
    "masks_available": list(loaded_masks.keys()),
}

stats_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_gt.json")
with open(stats_path, "w") as f:
    json.dump(stats, f, indent=2)

print(f"\nGround truth statistics saved to {stats_path}")
print(f"  Liver volume: {stats['liver_volume_ml']:.1f} mL")
print(f"  Tumor volume: {stats['tumor_volume_ml']:.1f} mL")
print(f"  Tumor count: {stats['tumor_count']}")
print(f"  Min distance: {stats['min_tumor_portal_distance_mm']:.1f} mm")
print(f"  Vascular invasion: {stats['vascular_invasion']}")

# Also convert CT to NIfTI for easier loading
nifti_path = os.path.join(target_dir, f"patient_{patient_num}_ct.nii.gz")
if not os.path.exists(nifti_path):
    try:
        slope = 1.0
        intercept = 0.0
        ct_int16 = ct_volume.astype(np.int16)
        ct_nii = nib.Nifti1Image(ct_int16, ct_affine)
        nib.save(ct_nii, nifti_path)
        print(f"Saved CT as NIfTI: {nifti_path}")
    except Exception as e:
        print(f"WARNING: Could not save CT NIfTI: {e}")
PYEOF

fi

# ============================================================
# Generate synthetic data if download failed
# ============================================================
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "Generating synthetic liver CT with tumors and portal vein..."

    TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
    mkdir -p "$TARGET_DIR"

    export PATIENT_NUM IRCADB_DIR GROUND_TRUTH_DIR
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
    from scipy.ndimage import distance_transform_edt, label as scipy_label
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import distance_transform_edt, label as scipy_label

patient_num = os.environ.get("PATIENT_NUM", "5")
ircadb_dir = os.environ.get("IRCADB_DIR", "/home/ga/Documents/SlicerData/IRCADb")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
target_dir = os.path.join(ircadb_dir, f"patient_{patient_num}")
os.makedirs(target_dir, exist_ok=True)

np.random.seed(42)

# ============================================================
# Realistic abdominal CT parameters
# ============================================================
# Use moderate dimensions for speed
nx, ny, nz = 256, 256, 120
spacing = (0.78125, 0.78125, 2.5)  # mm per voxel (typical abdominal CT)

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

voxel_volume_mm3 = float(np.prod(spacing))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

# ============================================================
# Generate CT volume with realistic HU values
# ============================================================
# Background air: -1000 HU
# Soft tissue: 20-60 HU
# Liver: 50-70 HU (slightly denser than soft tissue)
# Tumor: 30-50 HU (hypo-attenuating relative to liver)
# Portal vein (contrast): 120-180 HU
# Bone/spine: 300-800 HU
# Fat: -100 to -50 HU

print("Generating CT volume...")
ct_data = np.zeros((nx, ny, nz), dtype=np.int16)

# Fill with soft tissue background (with noise)
ct_data[:] = np.random.normal(40, 12, (nx, ny, nz)).astype(np.int16)

# Create body outline (elliptical)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (85**2)) <= 1.0

# Set air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# Create spine (vertebral body - bright bone, posterior)
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 14**2
    ct_data[:, :, z][spine_mask] = np.random.normal(500, 80, np.sum(spine_mask)).astype(np.int16)

# ============================================================
# Create label map: 1=liver, 2=tumor, 3=portal vein
# ============================================================
label_data = np.zeros((nx, ny, nz), dtype=np.int16)

# --- LIVER (label 1) ---
# Right-sided, large organ spanning slices 20-100
# Modeled as a large irregular ellipsoid
print("Creating liver...")
liver_cx, liver_cy = center_x - 25, center_y - 5  # Right side, slightly anterior

for z in range(20, 100):
    # Liver cross-section varies with z: largest in middle, tapers at edges
    z_frac = (z - 20) / 80.0
    # Bell-shaped profile
    z_scale = np.exp(-((z_frac - 0.4)**2) / (2 * 0.15**2))
    rx = 55 * z_scale  # max semi-axis x ~ 55 voxels
    ry = 45 * z_scale  # max semi-axis y ~ 45 voxels

    if rx < 5 or ry < 5:
        continue

    liver_slice = ((X - liver_cx)**2 / (rx**2) + (Y - liver_cy)**2 / (ry**2)) <= 1.0
    # Don't overlap with spine
    spine_mask_z = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 18**2
    liver_region = liver_slice & body_mask & ~spine_mask_z

    label_data[:, :, z][liver_region] = 1
    # Liver HU: 50-70
    ct_data[:, :, z][liver_region] = np.random.normal(60, 8, np.sum(liver_region)).astype(np.int16)

# --- TUMORS (label 2) ---
# Create 2 distinct tumors within the liver
print("Creating tumors...")

# Tumor 1: ~20mm diameter in right lobe
tumor1_cx, tumor1_cy, tumor1_cz = center_x - 40, center_y - 15, 55
tumor1_radius = int(10 / spacing[0])  # ~12.8 voxels = 10mm radius = 20mm diameter

# Tumor 2: ~12mm diameter, closer to portal vein
tumor2_cx, tumor2_cy, tumor2_cz = center_x - 15, center_y + 10, 50
tumor2_radius = int(6 / spacing[0])  # ~7.7 voxels = 6mm radius = 12mm diameter

for z in range(nz):
    # Tumor 1 (spherical)
    dz1 = abs(z - tumor1_cz) * spacing[2] / spacing[0]
    if dz1 < tumor1_radius:
        r_eff1 = np.sqrt(tumor1_radius**2 - dz1**2)
        t1_mask = ((X - tumor1_cx)**2 + (Y - tumor1_cy)**2) <= r_eff1**2
        in_liver = label_data[:, :, z] == 1
        tumor1_region = t1_mask & in_liver
        label_data[:, :, z][tumor1_region] = 2
        # Tumor HU: 30-50 (hypo-attenuating)
        ct_data[:, :, z][tumor1_region] = np.random.normal(40, 8, np.sum(tumor1_region)).astype(np.int16)

    # Tumor 2 (spherical, smaller)
    dz2 = abs(z - tumor2_cz) * spacing[2] / spacing[0]
    if dz2 < tumor2_radius:
        r_eff2 = np.sqrt(tumor2_radius**2 - dz2**2)
        t2_mask = ((X - tumor2_cx)**2 + (Y - tumor2_cy)**2) <= r_eff2**2
        in_liver = (label_data[:, :, z] == 1)
        tumor2_region = t2_mask & in_liver
        label_data[:, :, z][tumor2_region] = 2
        ct_data[:, :, z][tumor2_region] = np.random.normal(40, 8, np.sum(tumor2_region)).astype(np.int16)

# --- PORTAL VEIN (label 3) ---
# Main portal vein: runs roughly horizontal through liver hilum
# Enters liver from medial side, branches
print("Creating portal vein...")

# Main trunk: cylindrical, ~12mm diameter
pv_cy_start = center_y + 15  # starts posterior (hilum area)
pv_radius = int(6 / spacing[0])  # 6mm radius = 12mm diameter

for z in range(35, 70):
    # Main portal vein trunk runs along x-axis through liver hilum
    pv_cy_z = pv_cy_start - int((z - 35) * 0.1)  # slight anterior trajectory

    for x_offset in range(-30, 10):
        px = center_x + x_offset
        pv_mask = ((X - px)**2 + (Y - pv_cy_z)**2) <= pv_radius**2
        in_liver = (label_data[:, :, z] == 1)
        # Only place portal vein where we have liver (not tumor)
        pv_region = pv_mask & in_liver
        label_data[:, :, z][pv_region] = 3
        # Portal vein HU: 120-180 (contrast enhanced)
        ct_data[:, :, z][pv_region] = np.random.normal(150, 20, np.sum(pv_region)).astype(np.int16)

    # Right branch (going into right lobe)
    if z >= 45 and z <= 60:
        rpv_cx = center_x - 25
        rpv_cy = pv_cy_z - 5
        rpv_r = int(4 / spacing[0])
        rpv_mask = ((X - rpv_cx)**2 + (Y - rpv_cy)**2) <= rpv_r**2
        in_liver = (label_data[:, :, z] == 1)
        rpv_region = rpv_mask & in_liver
        label_data[:, :, z][rpv_region] = 3
        ct_data[:, :, z][rpv_region] = np.random.normal(150, 20, np.sum(rpv_region)).astype(np.int16)

# Add fat layer around body
fat_inner = ((X - center_x)**2 / (90**2) + (Y - center_y)**2 / (75**2)) <= 1.0
fat_outer = ((X - center_x)**2 / (95**2) + (Y - center_y)**2 / (80**2)) <= 1.0
fat_ring = fat_outer & ~fat_inner
for z in range(nz):
    fat_voxels = fat_ring & body_mask & (label_data[:, :, z] == 0)
    ct_data[:, :, z][fat_voxels] = np.random.normal(-80, 15, np.sum(fat_voxels)).astype(np.int16)

# ============================================================
# Save NIfTI files
# ============================================================
print("Saving NIfTI files...")

ct_img = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(target_dir, f"patient_{patient_num}_ct.nii.gz")
nib.save(ct_img, ct_path)
print(f"CT volume saved: {ct_path} (shape: {ct_data.shape})")

label_img = nib.Nifti1Image(label_data, affine)
gt_seg_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
nib.save(label_img, gt_seg_path)
print(f"Ground truth segmentation saved: {gt_seg_path}")

# ============================================================
# Compute ground truth statistics
# ============================================================
print("Computing ground truth statistics...")

liver_mask = (label_data == 1) | (label_data == 2)  # liver includes tumor area
tumor_mask = (label_data == 2)
portal_mask = (label_data == 3)

# Count distinct tumors
tumor_labeled, tumor_count = scipy_label(tumor_mask)
print(f"  Tumor count: {tumor_count}")

# Compute tumor-to-portal-vein distance
min_distance = float('inf')
if np.any(tumor_mask) and np.any(portal_mask):
    portal_dt = distance_transform_edt(~portal_mask, sampling=spacing)
    min_distance = float(portal_dt[tumor_mask].min())
    print(f"  Min tumor-portal distance: {min_distance:.2f} mm")

# Vascular invasion: contact if distance < 1mm
vascular_invasion = min_distance < 1.0

stats = {
    "patient_num": int(patient_num),
    "ct_shape": list(ct_data.shape),
    "voxel_spacing_mm": list(spacing),
    "voxel_volume_mm3": voxel_volume_mm3,
    "liver_volume_ml": float(np.sum(liver_mask) * voxel_volume_ml),
    "tumor_volume_ml": float(np.sum(tumor_mask) * voxel_volume_ml),
    "tumor_count": int(tumor_count),
    "portal_vein_voxels": int(np.sum(portal_mask)),
    "min_tumor_portal_distance_mm": float(min_distance) if not np.isinf(min_distance) else -1.0,
    "vascular_invasion": bool(vascular_invasion),
    "masks_available": ["liver", "tumor", "portal_vein"],
    "synthetic": True,
}

stats_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_gt.json")
with open(stats_path, "w") as f:
    json.dump(stats, f, indent=2)

print(f"\nGround truth statistics saved to {stats_path}")
print(f"  Liver volume: {stats['liver_volume_ml']:.1f} mL")
print(f"  Tumor volume: {stats['tumor_volume_ml']:.1f} mL")
print(f"  Tumor count: {stats['tumor_count']}")
print(f"  Portal vein voxels: {stats['portal_vein_voxels']}")
print(f"  Min tumor-portal distance: {stats['min_tumor_portal_distance_mm']:.2f} mm")
print(f"  Vascular invasion: {stats['vascular_invasion']}")
PYEOF

fi

# Set permissions
chown -R ga:ga "$IRCADB_DIR" 2>/dev/null || true
chmod -R 755 "$IRCADB_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Save patient number for other scripts
echo "$PATIENT_NUM" > /tmp/ircadb_patient_num

echo ""
echo "=== IRCADb Data Preparation Complete ==="
echo "Patient: $PATIENT_NUM"
echo "Data location: $IRCADB_DIR/patient_${PATIENT_NUM}/"
