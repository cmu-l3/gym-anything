#!/bin/bash
# Export script for brain_mri_key_images task
echo "=== Exporting brain_mri_key_images result ==="

export DISPLAY=:1

TASK_START=$(cat /tmp/brain_mri_key_images_start_ts 2>/dev/null || echo "0")
KEY_IMAGES_DIR="/home/ga/DICOM/exports/key_images"
SUMMARY_FILE="/home/ga/DICOM/exports/key_image_summary.txt"

# ------------------------------------------------------------------
# Take final screenshot
# ------------------------------------------------------------------
DISPLAY=:1 import -window root /tmp/brain_mri_key_images_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/brain_mri_key_images_end_screenshot.png 2>/dev/null || true

# ------------------------------------------------------------------
# Check each required key image
# ------------------------------------------------------------------
check_image() {
    local FILE="$1"
    local EXISTS=false
    local IS_NEW=false
    local SIZE_KB=0

    if [ -f "$FILE" ]; then
        EXISTS=true
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            IS_NEW=true
        fi
        SIZE_BYTES=$(stat -c %s "$FILE" 2>/dev/null || echo "0")
        SIZE_KB=$((SIZE_BYTES / 1024))
    fi

    echo "$EXISTS $IS_NEW $SIZE_KB"
}

IMG1_INFO=$(check_image "$KEY_IMAGES_DIR/key_image_01.png")
IMG2_INFO=$(check_image "$KEY_IMAGES_DIR/key_image_02.png")
IMG3_INFO=$(check_image "$KEY_IMAGES_DIR/key_image_03.png")

IMG1_EXISTS=$(echo "$IMG1_INFO" | awk '{print $1}')
IMG1_NEW=$(echo "$IMG1_INFO" | awk '{print $2}')
IMG1_SIZE=$(echo "$IMG1_INFO" | awk '{print $3}')

IMG2_EXISTS=$(echo "$IMG2_INFO" | awk '{print $1}')
IMG2_NEW=$(echo "$IMG2_INFO" | awk '{print $2}')
IMG2_SIZE=$(echo "$IMG2_INFO" | awk '{print $3}')

IMG3_EXISTS=$(echo "$IMG3_INFO" | awk '{print $1}')
IMG3_NEW=$(echo "$IMG3_INFO" | awk '{print $2}')
IMG3_SIZE=$(echo "$IMG3_INFO" | awk '{print $3}')

# Count how many valid new key images exist (exist AND new AND >= 20KB)
VALID_KEY_IMAGES=0
[ "$IMG1_EXISTS" = "true" ] && [ "$IMG1_NEW" = "true" ] && [ "$IMG1_SIZE" -ge 20 ] && VALID_KEY_IMAGES=$((VALID_KEY_IMAGES + 1))
[ "$IMG2_EXISTS" = "true" ] && [ "$IMG2_NEW" = "true" ] && [ "$IMG2_SIZE" -ge 20 ] && VALID_KEY_IMAGES=$((VALID_KEY_IMAGES + 1))
[ "$IMG3_EXISTS" = "true" ] && [ "$IMG3_NEW" = "true" ] && [ "$IMG3_SIZE" -ge 20 ] && VALID_KEY_IMAGES=$((VALID_KEY_IMAGES + 1))

# Count any new PNG files in the key_images directory (agent may have named them differently)
ANY_NEW_PNG_COUNT=0
if [ -d "$KEY_IMAGES_DIR" ]; then
    while IFS= read -r -d '' f; do
        FMTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            ANY_NEW_PNG_COUNT=$((ANY_NEW_PNG_COUNT + 1))
        fi
    done < <(find "$KEY_IMAGES_DIR" -maxdepth 1 -name "*.png" -print0 2>/dev/null)
fi

# Check for any new PNG in the broader exports directory (agent may have missed subdirectory)
EXPORTS_NEW_PNG_COUNT=0
if [ -d "/home/ga/DICOM/exports" ]; then
    while IFS= read -r -d '' f; do
        FMTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            EXPORTS_NEW_PNG_COUNT=$((EXPORTS_NEW_PNG_COUNT + 1))
        fi
    done < <(find "/home/ga/DICOM/exports" -name "*.png" -print0 2>/dev/null)
fi

# ------------------------------------------------------------------
# Check summary file
# ------------------------------------------------------------------
SUMMARY_EXISTS=false
SUMMARY_IS_NEW=false
SUMMARY_SIZE=0
WINDOW_MENTIONED=false
ANATOMICAL_LEVELS_MENTIONED=false
SLICE_INFO_MENTIONED=false

if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS=true
    SMTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
    if [ "$SMTIME" -gt "$TASK_START" ]; then
        SUMMARY_IS_NEW=true
    fi
    SUMMARY_SIZE=$(stat -c %s "$SUMMARY_FILE" 2>/dev/null || echo "0")

    if [ "$SUMMARY_IS_NEW" = "true" ]; then
        # Check for window/level mention (W:80 L:40 or window width 80 etc.)
        if grep -qiE "(window|W/L|WW|WL|80|40)" "$SUMMARY_FILE" 2>/dev/null; then
            WINDOW_MENTIONED=true
        fi

        # Check for anatomical level keywords
        if grep -qiE "(vertex|convex|basal|gangli|thalamus|cerebellum|posterior fossa|fourth ventricle|pons|brainstem|cortex|white matter|caudate|putamen)" "$SUMMARY_FILE" 2>/dev/null; then
            ANATOMICAL_LEVELS_MENTIONED=true
        fi

        # Check for slice number or position
        if grep -qiE "(slice|position|level|#[0-9]|no\.[[:space:]]*[0-9]|image [0-9]|series)" "$SUMMARY_FILE" 2>/dev/null; then
            SLICE_INFO_MENTIONED=true
        fi
    fi
fi

# ------------------------------------------------------------------
# Write result JSON
# ------------------------------------------------------------------
cat > /tmp/brain_mri_key_images_result.json << EOF
{
    "task_start": $TASK_START,
    "key_image_01_exists": $IMG1_EXISTS,
    "key_image_01_is_new": $IMG1_NEW,
    "key_image_01_size_kb": $IMG1_SIZE,
    "key_image_02_exists": $IMG2_EXISTS,
    "key_image_02_is_new": $IMG2_NEW,
    "key_image_02_size_kb": $IMG2_SIZE,
    "key_image_03_exists": $IMG3_EXISTS,
    "key_image_03_is_new": $IMG3_NEW,
    "key_image_03_size_kb": $IMG3_SIZE,
    "valid_key_images_count": $VALID_KEY_IMAGES,
    "any_new_png_in_key_images": $ANY_NEW_PNG_COUNT,
    "any_new_png_in_exports": $EXPORTS_NEW_PNG_COUNT,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_is_new": $SUMMARY_IS_NEW,
    "summary_size_bytes": $SUMMARY_SIZE,
    "window_mentioned_in_summary": $WINDOW_MENTIONED,
    "anatomical_levels_mentioned": $ANATOMICAL_LEVELS_MENTIONED,
    "slice_info_mentioned": $SLICE_INFO_MENTIONED
}
EOF

echo "=== brain_mri_key_images export complete ==="
echo "Valid key images (named correctly, new, >=20KB): $VALID_KEY_IMAGES"
echo "Any new PNG in key_images dir: $ANY_NEW_PNG_COUNT"
echo "Summary file exists: $SUMMARY_EXISTS, new: $SUMMARY_IS_NEW, size: $SUMMARY_SIZE bytes"
cat /tmp/brain_mri_key_images_result.json
