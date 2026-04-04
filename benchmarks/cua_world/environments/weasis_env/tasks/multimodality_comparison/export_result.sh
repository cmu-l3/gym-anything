#!/bin/bash
echo "=== Exporting multimodality_comparison result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/multimodality_end_screenshot.png

TASK_START=$(cat /tmp/multimodality_start_ts 2>/dev/null || echo "0")
EXPORT_IMAGE="/home/ga/DICOM/exports/comparison_view.png"
EXPORT_REPORT="/home/ga/DICOM/exports/comparison_report.txt"

# --- Check comparison image ---
IMAGE_EXISTS=false
IMAGE_IS_NEW=false
IMAGE_SIZE_KB=0

if [ -f "$EXPORT_IMAGE" ]; then
    IMAGE_EXISTS=true
    IMAGE_MTIME=$(stat -c %Y "$EXPORT_IMAGE" 2>/dev/null || echo "0")
    [ "$IMAGE_MTIME" -gt "$TASK_START" ] && IMAGE_IS_NEW=true
    IMAGE_SIZE_KB=$(( $(stat -c %s "$EXPORT_IMAGE" 2>/dev/null || echo "0") / 1024 ))
fi

# --- Check report ---
REPORT_EXISTS=false
REPORT_IS_NEW=false
REPORT_SIZE=0
CT_MEASUREMENT_FOUND=false
MRI_MEASUREMENT_FOUND=false
BOTH_MODALITIES_MENTIONED=false

if [ -f "$EXPORT_REPORT" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$EXPORT_REPORT" 2>/dev/null || echo "0")
    [ "$REPORT_MTIME" -gt "$TASK_START" ] && REPORT_IS_NEW=true
    REPORT_SIZE=$(stat -c %s "$EXPORT_REPORT" 2>/dev/null || echo "0")

    # Check for CT and MRI mentions
    grep -qiE "\bCT\b|computed tomography" "$EXPORT_REPORT" 2>/dev/null && CT_MEASUREMENT_FOUND=true
    grep -qiE "\bMRI\b|\bMR\b|magnetic resonance" "$EXPORT_REPORT" 2>/dev/null && MRI_MEASUREMENT_FOUND=true
    ( $CT_MEASUREMENT_FOUND && $MRI_MEASUREMENT_FOUND ) && BOTH_MODALITIES_MENTIONED=true
fi

# Number of new PNG files (comparison view might be multiple files)
NEW_PNG_COUNT=$(find /home/ga/DICOM/exports -name "*.png" -newer /tmp/multimodality_start_ts 2>/dev/null | wc -l)
ANY_NEW_PNG=$(find /home/ga/DICOM/exports -name "*.png" -newer /tmp/multimodality_start_ts 2>/dev/null | head -3 | tr '\n' ',')

cat > /tmp/multimodality_comparison_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_is_new": $IMAGE_IS_NEW,
    "image_size_kb": $IMAGE_SIZE_KB,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_size_bytes": $REPORT_SIZE,
    "ct_mentioned_in_report": $CT_MEASUREMENT_FOUND,
    "mri_mentioned_in_report": $MRI_MEASUREMENT_FOUND,
    "both_modalities_mentioned": $BOTH_MODALITIES_MENTIONED,
    "new_png_count": $NEW_PNG_COUNT,
    "any_new_png_exports": "$ANY_NEW_PNG"
}
JSONEOF

chmod 666 /tmp/multimodality_comparison_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/multimodality_comparison_result.json
echo ""
echo "=== Export Complete ==="
