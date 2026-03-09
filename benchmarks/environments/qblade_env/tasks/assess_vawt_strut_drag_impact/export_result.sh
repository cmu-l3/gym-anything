#!/bin/bash
echo "=== Exporting assess_vawt_strut_drag_impact results ==="

source /workspace/scripts/task_utils.sh

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
PROJECT_PATH="/home/ga/Documents/projects/vawt_strut_study.wpa"
REPORT_PATH="/home/ga/Documents/projects/strut_loss_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_EXISTS="true"
        PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
BASELINE_CP="0"
STRUTTED_CP="0"
LOSS_PERCENT="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Read first 1KB safely
        
        # Try to extract values using regex (simple bash extraction)
        # We rely on python verifier for robust parsing, but do a quick check here
        BASELINE_CP=$(grep -oP "Baseline.*?Cp.*?\K[0-9.]+" "$REPORT_PATH" | head -1 || echo "0")
        STRUTTED_CP=$(grep -oP "Strutted.*?Cp.*?\K[0-9.]+" "$REPORT_PATH" | head -1 || echo "0")
    fi
fi

# 3. Check App State
APP_RUNNING=$(is_qblade_running)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(jq -n --arg content "$REPORT_CONTENT" '$content'),
    "extracted_baseline": "$BASELINE_CP",
    "extracted_strutted": "$STRUTTED_CP",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="