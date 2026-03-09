#!/bin/bash
set -e
echo "=== Exporting Wilcoxon Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true
sleep 1
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Result Files
OMV_FILE="/home/ga/Documents/Jamovi/WilcoxonSignedRank.omv"
TXT_FILE="/home/ga/Documents/Jamovi/wilcoxon_results.txt"

OMV_EXISTS="false"
OMV_CREATED_DURING="false"
TXT_EXISTS="false"
TXT_CREATED_DURING="false"

if [ -f "$OMV_FILE" ]; then
    OMV_EXISTS="true"
    MTIME=$(stat -c %Y "$OMV_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    fi
fi

if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    MTIME=$(stat -c %Y "$TXT_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png",
    "omv_path": "$OMV_FILE",
    "txt_path": "$TXT_FILE",
    "ground_truth_path": "/var/lib/jamovi_ground_truth/expected_values.txt"
}
EOF

# 4. Save JSON to known location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"