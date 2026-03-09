#!/bin/bash
echo "=== Exporting radtech_ct_multiwindow_pathology_survey result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/radtech_multiwindow_end_screenshot.png

TASK_START=$(cat /tmp/radtech_multiwindow_start_ts 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"
REPORT_FILE="$EXPORT_DIR/multiwindow_survey_report.txt"

# --- Count PNG exports created after task start ---
PNG_COUNT=0
PNG_FILES=""
PNG_TOTAL_KB=0

if [ -d "$EXPORT_DIR" ]; then
    for png in "$EXPORT_DIR"/*.png; do
        [ -f "$png" ] || continue
        PNG_MTIME=$(stat -c %Y "$png" 2>/dev/null || echo "0")
        if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
            PNG_SIZE=$(( $(stat -c %s "$png" 2>/dev/null || echo "0") / 1024 ))
            if [ "$PNG_SIZE" -ge 5 ]; then
                PNG_COUNT=$((PNG_COUNT + 1))
                PNG_FILES="${PNG_FILES}$(basename "$png"):${PNG_SIZE}KB,"
                PNG_TOTAL_KB=$((PNG_TOTAL_KB + PNG_SIZE))
            fi
        fi
    done
fi

# --- Check report file ---
REPORT_EXISTS=false
REPORT_IS_NEW=false
REPORT_SIZE=0
REPORT_CONTENT=""
WINDOW_NAMES_FOUND=0
MEASUREMENT_COUNT=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_IS_NEW=true
    fi
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_CONTENT=$(head -c 2000 "$REPORT_FILE" 2>/dev/null || echo "")

    # Check for window preset names or values mentioned in report
    WINDOW_NAMES_FOUND=$(python3 -c "
import re
text = open('$REPORT_FILE', errors='replace').read().lower()
count = 0
# Check for window name mentions
if any(w in text for w in ['lung', 'pulmonary', 'airway']): count += 1
if any(w in text for w in ['bone', 'skeletal', 'osseous']): count += 1
if any(w in text for w in ['soft tissue', 'abdomen', 'liver', 'hepatic']): count += 1
if any(w in text for w in ['mediastin', 'vascular', 'cardiac', 'aort']): count += 1
# Also check for W/L value patterns
wl_matches = re.findall(r'[wW]\s*[:=]?\s*\d{2,4}', text)
if len(wl_matches) >= 2: count = max(count, min(len(wl_matches), 4))
print(count)
" 2>/dev/null || echo "0")

    # Count distinct numerical measurements in report
    MEASUREMENT_COUNT=$(python3 -c "
import re
text = open('$REPORT_FILE', errors='replace').read()
# Find numbers in 5-300mm range that could be measurements
nums = re.findall(r'\b(\d{1,3}\.?\d*)\s*(?:mm|millimeter|cm)?', text)
valid = set()
for n in nums:
    try:
        v = float(n)
        if 5 <= v <= 300:
            valid.add(round(v, 1))
    except: pass
print(len(valid))
" 2>/dev/null || echo "0")
fi

# --- Also check for any new PNG or JPEG anywhere under exports ---
ANY_NEW_IMAGES=$(find "$EXPORT_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -newer /tmp/radtech_multiwindow_start_ts 2>/dev/null | wc -l)

cat > /tmp/radtech_multiwindow_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "png_count": $PNG_COUNT,
    "png_files": "$PNG_FILES",
    "png_total_kb": $PNG_TOTAL_KB,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_size_bytes": $REPORT_SIZE,
    "window_names_found": $WINDOW_NAMES_FOUND,
    "measurement_count": $MEASUREMENT_COUNT,
    "any_new_images": $ANY_NEW_IMAGES
}
JSONEOF

chmod 666 /tmp/radtech_multiwindow_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/radtech_multiwindow_result.json
echo ""
echo "=== Export Complete ==="
