#!/bin/bash
echo "=== Exporting mpr_kidney_measurement result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/mpr_kidney_end_screenshot.png

TASK_START=$(cat /tmp/mpr_kidney_start_ts 2>/dev/null || echo "0")
EXPORT_IMAGE="/home/ga/DICOM/exports/mpr_renal.png"
EXPORT_REPORT="/home/ga/DICOM/exports/renal_report.txt"

# --- Check export image ---
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
KIDNEY_LENGTH_MM=""
NORMAL_ASSESSMENT_FOUND=false

if [ -f "$EXPORT_REPORT" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$EXPORT_REPORT" 2>/dev/null || echo "0")
    [ "$REPORT_MTIME" -gt "$TASK_START" ] && REPORT_IS_NEW=true
    REPORT_SIZE=$(stat -c %s "$EXPORT_REPORT" 2>/dev/null || echo "0")

    # Extract kidney length measurement (50-160mm range)
    KIDNEY_LENGTH_MM=$(python3 -c "
import re
text = open('$EXPORT_REPORT').read()
# Look for numbers in kidney length range (50-160mm)
matches = re.findall(r'\b((?:[5-9][0-9]|1[0-5][0-9]|160)(?:\.[0-9]+)?)\b', text)
if matches: print(matches[0])
else: print('')
" 2>/dev/null || echo "")

    # Check if normal/abnormal assessment is present
    grep -qiE "(normal|abnormal|enlarged|within limits|WNL|within normal)" "$EXPORT_REPORT" 2>/dev/null && NORMAL_ASSESSMENT_FOUND=true
fi

# Any new PNG files in exports
ANY_NEW_PNG=$(find /home/ga/DICOM/exports -name "*.png" -newer /tmp/mpr_kidney_start_ts 2>/dev/null | head -3 | tr '\n' ',')

cat > /tmp/mpr_kidney_measurement_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_is_new": $IMAGE_IS_NEW,
    "image_size_kb": $IMAGE_SIZE_KB,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_size_bytes": $REPORT_SIZE,
    "kidney_length_mm": "$KIDNEY_LENGTH_MM",
    "normal_assessment_found": $NORMAL_ASSESSMENT_FOUND,
    "any_new_png_exports": "$ANY_NEW_PNG"
}
JSONEOF

chmod 666 /tmp/mpr_kidney_measurement_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/mpr_kidney_measurement_result.json
echo ""
echo "=== Export Complete ==="
