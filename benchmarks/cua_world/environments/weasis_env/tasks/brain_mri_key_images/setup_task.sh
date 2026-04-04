#!/bin/bash
# Setup script for brain_mri_key_images task
# Occupation: Radiologic Technologist — neuroradiology key image protocol
echo "=== Setting up brain_mri_key_images ==="

export DISPLAY=:1

# ------------------------------------------------------------------
# STEP 1: Ensure brain MRI DICOM data is available
# We need real MRI data from rubomedical.com (dicom_viewer_0003.zip)
# This should have been downloaded by setup_weasis.sh (post_start hook)
# ------------------------------------------------------------------
MR_SOURCE="/home/ga/DICOM/samples/mr_scan"

if [ ! -d "$MR_SOURCE" ] || [ -z "$(ls -A "$MR_SOURCE" 2>/dev/null)" ]; then
    echo "ERROR: MRI DICOM data not found at $MR_SOURCE"
    echo "The post_start hook (setup_weasis.sh) should have downloaded it."
    echo "Cannot set up brain_mri_key_images task without real data."
    exit 1
fi

# ------------------------------------------------------------------
# STEP 2: Create task-specific study directory from real MRI data
# ------------------------------------------------------------------
BRAIN_MRI_DIR="/home/ga/DICOM/studies/brain_mri"
mkdir -p "$BRAIN_MRI_DIR"

# Copy the real MRI DICOM files into the task study directory
cp -r "$MR_SOURCE"/. "$BRAIN_MRI_DIR/"
chown -R ga:ga "$BRAIN_MRI_DIR"

MRI_FILE_COUNT=$(find "$BRAIN_MRI_DIR" -name "*.dcm" -o -name "*.DCM" 2>/dev/null | wc -l)
if [ "$MRI_FILE_COUNT" -eq 0 ]; then
    # Some DICOM files have no extension; count all regular files
    MRI_FILE_COUNT=$(find "$BRAIN_MRI_DIR" -type f 2>/dev/null | wc -l)
fi
echo "Brain MRI study prepared: $MRI_FILE_COUNT files in $BRAIN_MRI_DIR"

# ------------------------------------------------------------------
# STEP 3: Create exports directory and remove any stale outputs
# Remove BEFORE recording start timestamp to prevent false positives
# ------------------------------------------------------------------
KEY_IMAGES_DIR="/home/ga/DICOM/exports/key_images"
mkdir -p "$KEY_IMAGES_DIR"
chown -R ga:ga /home/ga/DICOM/exports

rm -f "$KEY_IMAGES_DIR/key_image_01.png" 2>/dev/null || true
rm -f "$KEY_IMAGES_DIR/key_image_02.png" 2>/dev/null || true
rm -f "$KEY_IMAGES_DIR/key_image_03.png" 2>/dev/null || true
rm -f "/home/ga/DICOM/exports/key_image_summary.txt" 2>/dev/null || true

# Remove any other PNG files in exports/key_images that might contaminate baseline
find "$KEY_IMAGES_DIR" -name "*.png" -delete 2>/dev/null || true

# ------------------------------------------------------------------
# STEP 4: Record task start timestamp (AFTER cleanup)
# ------------------------------------------------------------------
date +%s > /tmp/brain_mri_key_images_start_ts
echo "Task start timestamp recorded: $(cat /tmp/brain_mri_key_images_start_ts)"

# ------------------------------------------------------------------
# STEP 5: Ensure Weasis is running and accessible
# ------------------------------------------------------------------
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
    echo "Weasis not running — launching..."
    su - ga -c "DISPLAY=:1 /snap/bin/weasis >> /home/ga/weasis_launch.log 2>&1 &"
    # Wait up to 60 seconds for Weasis window
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
            echo "Weasis window appeared after $((i*2))s"
            break
        fi
        sleep 2
    done
fi

# ------------------------------------------------------------------
# STEP 6: Take initial screenshot
# ------------------------------------------------------------------
sleep 2
DISPLAY=:1 import -window root /tmp/brain_mri_key_images_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/brain_mri_key_images_start_screenshot.png 2>/dev/null || true

echo "=== brain_mri_key_images setup complete ==="
echo "Brain MRI data: $BRAIN_MRI_DIR ($MRI_FILE_COUNT files)"
echo "Export target: $KEY_IMAGES_DIR"
echo "Summary target: /home/ga/DICOM/exports/key_image_summary.txt"
