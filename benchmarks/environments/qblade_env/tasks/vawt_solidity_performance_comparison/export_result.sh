#!/bin/bash
echo "=== Exporting VAWT Solidity Comparison Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/solidity_study.wpa"
REPORT_PATH="/home/ga/Documents/projects/solidity_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
FILE_CREATED_DURING_TASK="false"
PROJECT_CONTENT_MATCHES=0

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Quick grep checks for key content in the project file (QBlade .wpa is text-based)
    # Check for chord lengths 0.15 and 0.3 (or 0.30)
    if grep -q "0.15" "$PROJECT_PATH" && grep -q "0.3" "$PROJECT_PATH"; then
        PROJECT_CONTENT_MATCHES=$((PROJECT_CONTENT_MATCHES + 1))
    fi
    # Check for DMS simulation keyword (often stored as algo type or similar)
    if grep -qi "DMS" "$PROJECT_PATH" || grep -qi "Double Multiple" "$PROJECT_PATH"; then
        PROJECT_CONTENT_MATCHES=$((PROJECT_CONTENT_MATCHES + 1))
    fi
    # Check for NACA 0018
    if grep -qi "NACA.*0018" "$PROJECT_PATH"; then
        PROJECT_CONTENT_MATCHES=$((PROJECT_CONTENT_MATCHES + 1))
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read first 10 lines of report for the verifier to parse
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Check App State
APP_RUNNING=$(is_qblade_running)

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "project_content_score": $PROJECT_CONTENT_MATCHES,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"