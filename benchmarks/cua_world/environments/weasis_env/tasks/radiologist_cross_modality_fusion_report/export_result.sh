#!/bin/bash
echo "=== Exporting radiologist_cross_modality_fusion_report result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/radiologist_crossmod_end_screenshot.png

TASK_START=$(cat /tmp/radiologist_crossmod_start_ts 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"
CT_PNG="$EXPORT_DIR/ct_crossmod.png"
MR_PNG="$EXPORT_DIR/mr_crossmod.png"
REPORT_FILE="$EXPORT_DIR/crossmodality_report.txt"

# --- Check CT PNG ---
CT_EXISTS=false
CT_IS_NEW=false
CT_SIZE_KB=0
if [ -f "$CT_PNG" ]; then
    CT_EXISTS=true
    CT_MTIME=$(stat -c %Y "$CT_PNG" 2>/dev/null || echo "0")
    [ "$CT_MTIME" -gt "$TASK_START" ] && CT_IS_NEW=true
    CT_SIZE_KB=$(( $(stat -c %s "$CT_PNG" 2>/dev/null || echo "0") / 1024 ))
fi

# --- Check MR PNG ---
MR_EXISTS=false
MR_IS_NEW=false
MR_SIZE_KB=0
if [ -f "$MR_PNG" ]; then
    MR_EXISTS=true
    MR_MTIME=$(stat -c %Y "$MR_PNG" 2>/dev/null || echo "0")
    [ "$MR_MTIME" -gt "$TASK_START" ] && MR_IS_NEW=true
    MR_SIZE_KB=$(( $(stat -c %s "$MR_PNG" 2>/dev/null || echo "0") / 1024 ))
fi

TOTAL_NEW_PNG=$(find "$EXPORT_DIR" -name "*.png" -newer /tmp/radiologist_crossmod_start_ts 2>/dev/null | wc -l)

# --- Check report ---
REPORT_EXISTS=false
REPORT_IS_NEW=false
REPORT_SIZE=0
HAS_CT_MENTION=false
HAS_MR_MENTION=false
MEASUREMENT_COUNT=0
HAS_COMPARATIVE=false

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    [ "$REPORT_MTIME" -gt "$TASK_START" ] && REPORT_IS_NEW=true
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")

    # Check for CT mention with measurement context
    HAS_CT_MENTION=$(python3 -c "
import re
text = open('$REPORT_FILE', errors='replace').read()
# CT mentioned near a number
ct_pattern = re.search(r'CT.*?\d+\.?\d*\s*(?:mm|cm)?|[Cc]omputed\s+[Tt]omography.*?\d', text)
# Or just CT mentioned at all
ct_simple = 'CT' in text.upper() or 'computed tomography' in text.lower()
print('true' if (ct_pattern or ct_simple) else 'false')
" 2>/dev/null || echo "false")

    HAS_MR_MENTION=$(python3 -c "
import re
text = open('$REPORT_FILE', errors='replace').read()
mr_pattern = re.search(r'MR[I]?.*?\d+\.?\d*\s*(?:mm|cm)?|[Mm]agnetic\s+[Rr]esonance.*?\d', text)
mr_simple = any(k in text for k in ['MRI', 'MR ', 'magnetic resonance'])
print('true' if (mr_pattern or mr_simple) else 'false')
" 2>/dev/null || echo "false")

    MEASUREMENT_COUNT=$(python3 -c "
import re
text = open('$REPORT_FILE', errors='replace').read()
nums = re.findall(r'\b(\d{1,3}\.?\d*)\s*(?:mm|millimeter|cm)?', text)
valid = set()
for n in nums:
    try:
        v = float(n)
        if 1 <= v <= 300:
            valid.add(round(v, 1))
    except: pass
print(len(valid))
" 2>/dev/null || echo "0")

    HAS_COMPARATIVE=$(python3 -c "
text = open('$REPORT_FILE', errors='replace').read().lower()
keywords = ['advantage', 'superior', 'better', 'resolution', 'contrast',
            'compared to', 'comparison', 'versus', 'vs', 'difference',
            'preferred', 'complementary', 'relative', 'sensitivity',
            'specificity', 'soft tissue contrast', 'spatial resolution',
            'percent', '%']
found = sum(1 for k in keywords if k in text)
print('true' if found >= 2 else 'false')
" 2>/dev/null || echo "false")
fi

cat > /tmp/radiologist_crossmod_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "ct_exists": $CT_EXISTS,
    "ct_is_new": $CT_IS_NEW,
    "ct_size_kb": $CT_SIZE_KB,
    "mr_exists": $MR_EXISTS,
    "mr_is_new": $MR_IS_NEW,
    "mr_size_kb": $MR_SIZE_KB,
    "total_new_png": $TOTAL_NEW_PNG,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "report_size_bytes": $REPORT_SIZE,
    "has_ct_mention": $HAS_CT_MENTION,
    "has_mr_mention": $HAS_MR_MENTION,
    "measurement_count": $MEASUREMENT_COUNT,
    "has_comparative": $HAS_COMPARATIVE
}
JSONEOF

chmod 666 /tmp/radiologist_crossmod_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/radiologist_crossmod_result.json
echo ""
echo "=== Export Complete ==="
