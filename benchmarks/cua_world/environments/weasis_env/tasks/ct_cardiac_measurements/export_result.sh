#!/bin/bash
echo "=== Exporting ct_cardiac_measurements result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/ct_cardiac_end_screenshot.png

TASK_START=$(cat /tmp/ct_cardiac_start_ts 2>/dev/null || echo "0")
EXPORT_IMAGE="/home/ga/DICOM/exports/cardiac_analysis.png"
EXPORT_REPORT="/home/ga/DICOM/exports/cardiac_report.txt"

# --- Check export image ---
IMAGE_EXISTS=false
IMAGE_IS_NEW=false
IMAGE_SIZE_KB=0

if [ -f "$EXPORT_IMAGE" ]; then
    IMAGE_EXISTS=true
    IMAGE_MTIME=$(stat -c %Y "$EXPORT_IMAGE" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_IS_NEW=true
    fi
    IMAGE_SIZE_KB=$(( $(stat -c %s "$EXPORT_IMAGE" 2>/dev/null || echo "0") / 1024 ))
fi

# --- Check report text file ---
REPORT_EXISTS=false
REPORT_IS_NEW=false
REPORT_SIZE=0
REPORT_CONTENT=""
CTR_VALUE=""
CARDIAC_WIDTH=""
THORACIC_WIDTH=""

if [ -f "$EXPORT_REPORT" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$EXPORT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_IS_NEW=true
    fi
    REPORT_SIZE=$(stat -c %s "$EXPORT_REPORT" 2>/dev/null || echo "0")
    # Read report content (first 500 chars)
    REPORT_CONTENT=$(head -c 500 "$EXPORT_REPORT" 2>/dev/null || echo "")
    # Extract any decimal number that could be a CTR (0.3-0.75 range)
    CTR_VALUE=$(python3 -c "
import re, sys
text = open('$EXPORT_REPORT').read()
# Look for decimal values that could be CTR (0.30 to 0.75)
matches = re.findall(r'0\.[3-7][0-9]', text)
if matches:
    print(matches[0])
else:
    # Also look for slightly wider range
    matches2 = re.findall(r'0\.\d{1,3}', text)
    print(matches2[0] if matches2 else '')
" 2>/dev/null || echo "")
    # Extract cardiac/thoracic widths (look for numbers that could be mm measurements)
    CARDIAC_WIDTH=$(python3 -c "
import re
text = open('$EXPORT_REPORT').read()
# Look for numbers in 50-200mm range (cardiac width)
matches = re.findall(r'([0-9]{2,3}\.?[0-9]*)\s*(?:mm|millimeter)', text, re.IGNORECASE)
if matches: print(matches[0])
else:
    # Just find first 2-3 digit number
    m = re.findall(r'\b([5-9][0-9]|1[0-9]{2})\b', text)
    print(m[0] if m else '')
" 2>/dev/null || echo "")
fi

# --- Also look for exported files elsewhere ---
ANY_NEW_PNG=$(find /home/ga/DICOM/exports -name "*.png" -newer /tmp/ct_cardiac_start_ts 2>/dev/null | head -3 | tr '\n' ',')

cat > /tmp/ct_cardiac_measurements_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_is_new": $IMAGE_IS_NEW,
    "image_size_kb": $IMAGE_SIZE_KB,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_size_bytes": $REPORT_SIZE,
    "ctr_value_found": "$CTR_VALUE",
    "cardiac_width_mm": "$CARDIAC_WIDTH",
    "any_new_png_exports": "$ANY_NEW_PNG"
}
JSONEOF

chmod 666 /tmp/ct_cardiac_measurements_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/ct_cardiac_measurements_result.json
echo ""
echo "=== Export Complete ==="
