#!/bin/bash
echo "=== Exporting process_capability_tooth_growth results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JASP_PATH="/home/ga/Documents/JASP/capability_analysis.jasp"
REPORT_PATH="/home/ga/Documents/JASP/cpk_report.txt"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check JASP file
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_MODIFIED_IN_TASK="false"

if [ -f "$JASP_PATH" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_PATH")
    JASP_MTIME=$(stat -c %Y "$JASP_PATH")
    if [ "$JASP_MTIME" -ge "$TASK_START" ]; then
        JASP_MODIFIED_IN_TASK="true"
    fi
fi

# 3. Check Report file
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MODIFIED_IN_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_MODIFIED_IN_TASK="true"
    fi
    # Read first line, limit length
    REPORT_CONTENT=$(head -n 1 "$REPORT_PATH" | tr -d '\n' | cut -c1-50)
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_exists": $JASP_EXISTS,
    "jasp_size": $JASP_SIZE,
    "jasp_created_during_task": $JASP_MODIFIED_IN_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "report_created_during_task": $REPORT_MODIFIED_IN_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "jasp_path": "$JASP_PATH"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# Copy JASP file to /tmp for verifier access (if it exists)
if [ "$JASP_EXISTS" = "true" ]; then
    cp "$JASP_PATH" /tmp/analysis_artifact.jasp
    chmod 644 /tmp/analysis_artifact.jasp
fi

echo "Export complete. Result:"
cat /tmp/task_result.json