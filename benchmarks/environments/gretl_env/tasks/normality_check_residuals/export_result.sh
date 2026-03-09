#!/bin/bash
echo "=== Exporting normality_check_residuals result ==="

source /workspace/scripts/task_utils.sh

# 1. Final Screenshot and App State
take_screenshot /tmp/task_final.png
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Text Output (Normality Test)
TEXT_FILE="/home/ga/Documents/gretl_output/normality_test.txt"
TEXT_EXISTS="false"
TEXT_CREATED_DURING="false"
TEXT_CONTENT=""

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING="true"
    fi
    # Read content for verifier (limit size)
    TEXT_CONTENT=$(head -n 50 "$TEXT_FILE" | base64 -w 0)
fi

# 3. Check Image Output (Histogram)
IMG_FILE="/home/ga/Documents/gretl_output/residual_hist.png"
IMG_EXISTS="false"
IMG_CREATED_DURING="false"
IMG_SIZE="0"

if [ -f "$IMG_FILE" ]; then
    IMG_EXISTS="true"
    MTIME=$(stat -c %Y "$IMG_FILE" 2>/dev/null || echo "0")
    SIZE=$(stat -c %s "$IMG_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING="true"
    fi
    IMG_SIZE="$SIZE"
fi

# 4. Include Ground Truth
TRUTH_CONTENT=""
if [ -f "/var/lib/gretl/truth_stats.txt" ]; then
    TRUTH_CONTENT=$(cat /var/lib/gretl/truth_stats.txt | base64 -w 0)
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "text_file_exists": $TEXT_EXISTS,
    "text_created_during_task": $TEXT_CREATED_DURING,
    "text_content_b64": "$TEXT_CONTENT",
    "image_file_exists": $IMG_EXISTS,
    "image_created_during_task": $IMG_CREATED_DURING,
    "image_size": $IMG_SIZE,
    "ground_truth_b64": "$TRUTH_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"