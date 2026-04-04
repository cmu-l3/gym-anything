#!/bin/bash
echo "=== Exporting task results ==="

# Paths
DOCS_DIR="/c/Users/Docker/Documents"
REPORT_PATH="$DOCS_DIR/alert_report.txt"
IMAGE_PATH="$DOCS_DIR/control_chart.png"
GROUND_TRUTH="$DOCS_DIR/ground_truth_metrics.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr -d '\r' | base64 -w 0)
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Image File
IMAGE_EXISTS="false"
IMAGE_CREATED_DURING_TASK="false"
IMAGE_SIZE="0"

if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "EpiInfo" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take final screenshot
scrot /tmp/task_final.png 2>/dev/null || import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Read Ground Truth (generated in setup)
GT_CONTENT=""
if [ -f "$GROUND_TRUTH" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH" | tr -d '\r' | base64 -w 0)
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "image_exists": $IMAGE_EXISTS,
    "image_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "image_size_bytes": $IMAGE_SIZE,
    "ground_truth_b64": "$GT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to expected location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="