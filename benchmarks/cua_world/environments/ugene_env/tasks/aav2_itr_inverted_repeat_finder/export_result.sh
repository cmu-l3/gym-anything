#!/bin/bash
echo "=== Exporting AAV2 ITR task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/UGENE_Data/gene_therapy/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check GenBank file
GB_FILE="${RESULTS_DIR}/aav2_annotated.gb"
GB_EXISTS="false"
GB_CREATED_DURING_TASK="false"
GB_VALID="false"
HAS_REPEAT_FEATURES="false"
REPEAT_COORDS=""

if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
    if [ "$GB_MTIME" -gt "$TASK_START" ]; then
        GB_CREATED_DURING_TASK="true"
    fi
    
    CONTENT=$(cat "$GB_FILE" 2>/dev/null)
    
    # Check if valid GB
    if echo "$CONTENT" | grep -q "^LOCUS" && echo "$CONTENT" | grep -q "^FEATURES"; then
        GB_VALID="true"
    fi
    
    # Extract repeat features
    if echo "$CONTENT" | grep -qi "repeat"; then
        HAS_REPEAT_FEATURES="true"
        REPEAT_COORDS=$(echo "$CONTENT" | grep -iA1 "repeat" | grep -oP '\d+\.\.\d+' | tr '\n' ',' | sed 's/,$//')
        if [ -z "$REPEAT_COORDS" ]; then
            REPEAT_COORDS=$(echo "$CONTENT" | grep -oP '(\d+\.\.\d+)' | tr '\n' ',' | sed 's/,$//')
        fi
    fi
fi

# Check Report file
REPORT_FILE="${RESULTS_DIR}/itr_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 1000)
fi

# Determine if UGENE is running
APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "gb_exists": $GB_EXISTS,
    "gb_created_during_task": $GB_CREATED_DURING_TASK,
    "gb_valid": $GB_VALID,
    "has_repeat_features": $HAS_REPEAT_FEATURES,
    "repeat_coords": "$REPEAT_COORDS",
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT"
}
EOF

# Move to /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="