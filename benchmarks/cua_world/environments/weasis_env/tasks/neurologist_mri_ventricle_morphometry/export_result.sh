#!/bin/bash
echo "=== Exporting neurologist_mri_ventricle_morphometry result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/neurologist_ventricle_end_screenshot.png

TASK_START=$(cat /tmp/neurologist_ventricle_start_ts 2>/dev/null || echo "0")
EXPORT_IMAGE="/home/ga/DICOM/exports/evans_index_measurement.png"
EXPORT_REPORT="/home/ga/DICOM/exports/nph_assessment_report.txt"
EXPORT_DIR="/home/ga/DICOM/exports"

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

# Check for any new PNG in exports
ANY_NEW_PNG=$(find "$EXPORT_DIR" -name "*.png" -newer /tmp/neurologist_ventricle_start_ts 2>/dev/null | wc -l)

# --- Check report ---
REPORT_EXISTS=false
REPORT_IS_NEW=false
REPORT_SIZE=0
EVANS_INDEX=""
MEASUREMENT_COUNT=0
HAS_CLINICAL_DETERMINATION=false

if [ -f "$EXPORT_REPORT" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$EXPORT_REPORT" 2>/dev/null || echo "0")
    [ "$REPORT_MTIME" -gt "$TASK_START" ] && REPORT_IS_NEW=true
    REPORT_SIZE=$(stat -c %s "$EXPORT_REPORT" 2>/dev/null || echo "0")

    # Extract Evans index value
    EVANS_INDEX=$(python3 -c "
import re
text = open('$EXPORT_REPORT', errors='replace').read()
# Look for Evans index value - decimal between 0.15 and 0.60
matches = re.findall(r'(?:evans|index|ratio).*?(0\.\d{1,3})', text, re.IGNORECASE)
if matches:
    print(matches[0])
else:
    # Also look for any standalone decimal in that range
    all_dec = re.findall(r'0\.[1-5]\d', text)
    print(all_dec[0] if all_dec else '')
" 2>/dev/null || echo "")

    # Count distinct measurements
    MEASUREMENT_COUNT=$(python3 -c "
import re
text = open('$EXPORT_REPORT', errors='replace').read()
nums = re.findall(r'\b(\d{1,3}\.?\d*)\s*(?:mm|millimeter)?', text)
valid = set()
for n in nums:
    try:
        v = float(n)
        if 1 <= v <= 200:
            valid.add(round(v, 1))
    except: pass
print(len(valid))
" 2>/dev/null || echo "0")

    # Check for clinical determination keywords
    HAS_CLINICAL_DETERMINATION=$(python3 -c "
text = open('$EXPORT_REPORT', errors='replace').read().lower()
keywords = ['ventriculomegaly', 'hydrocephalus', 'nph', 'normal pressure',
            'dilated', 'enlarged ventricle', 'within normal', 'no evidence',
            'suggestive', 'consistent with', 'exceeds threshold', 'below threshold']
found = any(k in text for k in keywords)
print('true' if found else 'false')
" 2>/dev/null || echo "false")
fi

cat > /tmp/neurologist_ventricle_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_is_new": $IMAGE_IS_NEW,
    "image_size_kb": $IMAGE_SIZE_KB,
    "any_new_png": $ANY_NEW_PNG,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_size_bytes": $REPORT_SIZE,
    "evans_index": "$EVANS_INDEX",
    "measurement_count": $MEASUREMENT_COUNT,
    "has_clinical_determination": $HAS_CLINICAL_DETERMINATION
}
JSONEOF

chmod 666 /tmp/neurologist_ventricle_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/neurologist_ventricle_result.json
echo ""
echo "=== Export Complete ==="
