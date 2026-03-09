#!/bin/bash
# Prepare BraTS 2021 data for brain tumor segmentation task
# Downloads REAL BraTS data from Kaggle

set -e

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
DOWNLOAD_DIR="/tmp/brats_download"
SAMPLE_ID="${1:-BraTS2021_00000}"

echo "=== Preparing BraTS 2021 Data ==="
echo "Data directory: $BRATS_DIR"
echo "Sample ID: $SAMPLE_ID"

mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$DOWNLOAD_DIR"

# Check if data already exists
if [ -f "$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz" ] && \
   [ -f "$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1.nii.gz" ] && \
   [ -f "$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz" ] && \
   [ -f "$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t2.nii.gz" ]; then
    echo "BraTS data already exists for $SAMPLE_ID"
    exit 0
fi

# Download BraTS 2021 dataset from Kaggle
echo "Downloading BraTS 2021 dataset from Kaggle..."
echo "This may take several minutes (~5GB download)..."

cd "$DOWNLOAD_DIR"

# Download using curl (no authentication required for this dataset)
if [ ! -f "brats-2021-task1.zip" ]; then
    echo "Downloading dataset..."
    curl -L -o brats-2021-task1.zip \
        https://www.kaggle.com/api/v1/datasets/download/dschettler8845/brats-2021-task1

    if [ ! -f "brats-2021-task1.zip" ]; then
        echo "ERROR: Failed to download BraTS dataset"
        exit 1
    fi

    # Verify file size (should be > 1GB at minimum)
    FILE_SIZE=$(stat -c%s "brats-2021-task1.zip" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -lt 1000000000 ]; then
        echo "ERROR: Downloaded file is too small (${FILE_SIZE} bytes). Download may have failed."
        rm -f brats-2021-task1.zip
        exit 1
    fi
    echo "Download complete: $(du -h brats-2021-task1.zip | cut -f1)"
fi

# Extract the dataset - the zip contains .tar files for each case
echo "Extracting dataset (zip -> tar files)..."
unzip -o -q brats-2021-task1.zip

# List what we got
echo "Extracted files:"
ls -la "$DOWNLOAD_DIR"/*.tar 2>/dev/null | head -10 || echo "No .tar files found"

# The Kaggle BraTS dataset contains individual tar files for each case
# e.g., BraTS2021_00000.tar, BraTS2021_00001.tar, etc.
# Each tar contains a directory with the NIfTI files

# Find available case tar files
AVAILABLE_TARS=$(ls "$DOWNLOAD_DIR"/BraTS2021_*.tar 2>/dev/null | head -10)
if [ -z "$AVAILABLE_TARS" ]; then
    # Maybe the structure is BraTS2021_Training_Data.tar
    if [ -f "BraTS2021_Training_Data.tar" ]; then
        echo "Found BraTS2021_Training_Data.tar, extracting..."
        tar -xf BraTS2021_Training_Data.tar
        AVAILABLE_TARS=$(ls "$DOWNLOAD_DIR"/BraTS2021_*.tar 2>/dev/null | head -10)
    fi
fi

if [ -z "$AVAILABLE_TARS" ]; then
    echo "ERROR: No BraTS case tar files found"
    ls -la "$DOWNLOAD_DIR"
    exit 1
fi

echo "Available case archives:"
echo "$AVAILABLE_TARS" | head -5

# Try to find the requested sample, or use first available
TARGET_TAR="$DOWNLOAD_DIR/${SAMPLE_ID}.tar"
if [ ! -f "$TARGET_TAR" ]; then
    echo "Specified case $SAMPLE_ID not found, using first available case..."
    TARGET_TAR=$(ls "$DOWNLOAD_DIR"/BraTS2021_*.tar | head -1)
    SAMPLE_ID=$(basename "$TARGET_TAR" .tar)
    echo "Using case: $SAMPLE_ID"
fi

# Extract the specific case
echo "Extracting $SAMPLE_ID..."
mkdir -p "$BRATS_DIR"
tar -xf "$TARGET_TAR" -C "$BRATS_DIR"

# The tar might create a subdirectory, or put files directly
# Check if files are in a subdirectory
if [ -d "$BRATS_DIR/$SAMPLE_ID" ]; then
    CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
elif [ -f "$BRATS_DIR/${SAMPLE_ID}_flair.nii.gz" ]; then
    # Files extracted to root, move them to subdirectory
    mkdir -p "$BRATS_DIR/$SAMPLE_ID"
    mv "$BRATS_DIR/${SAMPLE_ID}_"*.nii.gz "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || true
    CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
else
    # Look for any extracted directory
    FOUND_DIR=$(find "$BRATS_DIR" -maxdepth 1 -type d -name "BraTS*" | head -1)
    if [ -n "$FOUND_DIR" ]; then
        CASE_DIR="$FOUND_DIR"
        SAMPLE_ID=$(basename "$FOUND_DIR")
    else
        echo "ERROR: Could not find extracted case data"
        ls -la "$BRATS_DIR"
        exit 1
    fi
fi

echo "Case directory: $CASE_DIR"
echo "Contents:"
ls -la "$CASE_DIR"

# Move segmentation ground truth to hidden directory
if [ -f "$CASE_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "Moving ground truth segmentation to hidden location..."
    mv "$CASE_DIR/${SAMPLE_ID}_seg.nii.gz" "$GROUND_TRUTH_DIR/"

    # Calculate and save tumor statistics from ground truth
    python3 << PYEOF
import nibabel as nib
import numpy as np
import json
import os

gt_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
stats_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_stats.json"

# Load ground truth
gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

# Calculate statistics (BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing)
stats = {
    "sample_id": "$SAMPLE_ID",
    "shape": list(gt_data.shape),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_mm3": voxel_volume_mm3,
    "total_tumor_voxels": int(np.sum(gt_data > 0)),
    "necrotic_voxels": int(np.sum(gt_data == 1)),
    "edema_voxels": int(np.sum(gt_data == 2)),
    "enhancing_voxels": int(np.sum(gt_data == 4)),
    "total_tumor_volume_mm3": float(np.sum(gt_data > 0) * voxel_volume_mm3),
    "total_tumor_volume_ml": float(np.sum(gt_data > 0) * voxel_volume_mm3 / 1000),
}

with open(stats_path, 'w') as f:
    json.dump(stats, f, indent=2)

print(f"Ground truth statistics saved to {stats_path}")
print(f"  Total tumor volume: {stats['total_tumor_volume_ml']:.2f} mL")
PYEOF
fi

# Verify required files exist
echo "Verifying data files..."
REQUIRED_FILES=(
    "${SAMPLE_ID}_flair.nii.gz"
    "${SAMPLE_ID}_t1.nii.gz"
    "${SAMPLE_ID}_t1ce.nii.gz"
    "${SAMPLE_ID}_t2.nii.gz"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$CASE_DIR/$f" ]; then
        echo "ERROR: Missing required file: $CASE_DIR/$f"
        ls -la "$CASE_DIR"
        exit 1
    fi
    echo "  Found: $f ($(du -h "$CASE_DIR/$f" | cut -f1))"
done

# Verify ground truth
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "  Ground truth verified (hidden from agent)"

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Save the sample ID for other scripts
echo "$SAMPLE_ID" > /tmp/brats_sample_id

# Cleanup tar files to save space (keep zip for potential re-extraction)
echo "Cleaning up extracted tar files..."
rm -f "$DOWNLOAD_DIR"/BraTS2021_*.tar 2>/dev/null || true

echo ""
echo "=== BraTS Data Preparation Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "Data location: $CASE_DIR/"
echo "Files:"
ls -la "$CASE_DIR/"
