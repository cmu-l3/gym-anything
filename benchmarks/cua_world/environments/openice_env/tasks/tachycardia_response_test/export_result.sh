#!/bin/bash
echo "=== Exporting Tachycardia Response Test Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (fallback if agent didn't take one)
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get Window counts
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Get new log lines
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# 1. Verify Device Creation (Multiparameter Monitor)
DEVICE_CREATED="false"
# Check logs
if echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|vital.*monitor"; then
    DEVICE_CREATED="true"
fi
# Check window titles
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter|multiParam"; then
    DEVICE_CREATED="true"
fi

# 2. Verify App Launch (Vital Signs)
APP_LAUNCHED="false"
# Check logs
if echo "$NEW_LOG" | grep -qiE "vital.?signs|VitalSigns|clinical.*app"; then
    APP_LAUNCHED="true"
fi
# Check window titles
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "vital.?signs|VitalSigns"; then
    APP_LAUNCHED="true"
fi

# 3. Verify Evidence Screenshot
EVIDENCE_PATH="/home/ga/Desktop/tachycardia_alarm_evidence.png"
EVIDENCE_EXISTS="false"
EVIDENCE_SIZE=0
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_EXISTS="true"
        EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    fi
fi

# 4. Verify Report Content
REPORT_PATH="/home/ga/Desktop/simulation_verification_log.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
MAX_HR_FOUND=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
        
        # Extract numbers from report to find max heart rate mentioned
        # Looks for numbers between 100 and 300
        NUMBERS=$(echo "$REPORT_CONTENT" | grep -oE '[0-9]+')
        for num in $NUMBERS; do
            if [ "$num" -ge 150 ] && [ "$num" -le 300 ]; then
                if [ "$num" -gt "$MAX_HR_FOUND" ]; then
                    MAX_HR_FOUND=$num
                fi
            fi
        done
    fi
fi

# 5. Check keywords in report
REPORT_HAS_KEYWORDS="false"
if echo "$REPORT_CONTENT" | grep -qiE "red|alarm|flash|alert|color|warn"; then
    REPORT_HAS_KEYWORDS="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "device_created": $DEVICE_CREATED,
    "app_launched": $APP_LAUNCHED,
    "window_increase": $WINDOW_INCREASE,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_path": "$EVIDENCE_PATH",
    "report_exists": $REPORT_EXISTS,
    "max_hr_found": $MAX_HR_FOUND,
    "report_has_keywords": $REPORT_HAS_KEYWORDS,
    "report_content_preview": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF

# If evidence screenshot exists, copy it to a temp location readable by verifier
if [ "$EVIDENCE_EXISTS" = "true" ]; then
    cp "$EVIDENCE_PATH" /tmp/evidence_copy.png 2>/dev/null || true
    chmod 666 /tmp/evidence_copy.png 2>/dev/null || true
fi

echo "=== Export Complete ==="
cat /tmp/task_result.json