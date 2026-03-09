#!/bin/bash
set -e

echo "=== Exporting kernel_density_comparison results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Check if application was running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 3. Define output paths
STATS_FILE="/home/ga/Documents/gretl_output/group_stats.txt"
IMG_FILE="/home/ga/Documents/gretl_output/kde_comparison.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Check Stats File
STATS_EXISTS="false"
STATS_CREATED_DURING="false"
STATS_SIZE="0"
if [ -f "$STATS_FILE" ]; then
    STATS_EXISTS="true"
    STATS_SIZE=$(stat -c%s "$STATS_FILE" 2>/dev/null || echo "0")
    STATS_MTIME=$(stat -c%Y "$STATS_FILE" 2>/dev/null || echo "0")
    if [ "$STATS_MTIME" -gt "$TASK_START" ]; then
        STATS_CREATED_DURING="true"
    fi
fi

# 5. Check Image File
IMG_EXISTS="false"
IMG_CREATED_DURING="false"
IMG_SIZE="0"
if [ -f "$IMG_FILE" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c%s "$IMG_FILE" 2>/dev/null || echo "0")
    IMG_MTIME=$(stat -c%Y "$IMG_FILE" 2>/dev/null || echo "0")
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING="true"
    fi
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "stats_file_exists": $STATS_EXISTS,
    "stats_file_created_during_task": $STATS_CREATED_DURING,
    "stats_file_size": $STATS_SIZE,
    "stats_file_path": "$STATS_FILE",
    "image_file_exists": $IMG_EXISTS,
    "image_file_created_during_task": $IMG_CREATED_DURING,
    "image_file_size": $IMG_SIZE,
    "image_file_path": "$IMG_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="