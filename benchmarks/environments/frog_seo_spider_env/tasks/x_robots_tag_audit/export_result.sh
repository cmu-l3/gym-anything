#!/bin/bash
# Export result script for X-Robots-Tag Audit

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting X-Robots-Tag Audit Result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TARGET_FILE="$EXPORT_DIR/x_robots_header_report.csv"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
ROW_COUNT=0
HAS_X_ROBOTS_HEADER="false"
HAS_TARGET_URLS="false"
SF_RUNNING="false"

# Check if Screaming Frog is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Check file existence and properties
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Basic content analysis using grep/wc
    ROW_COUNT=$(wc -l < "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check for X-Robots-Tag header in CSV (usually "X-Robots-Tag 1" or similar)
    if grep -qi "X-Robots-Tag" "$TARGET_FILE"; then
        HAS_X_ROBOTS_HEADER="true"
    fi

    # Check for presence of known test URLs for X-Robots-Tag
    # e.g., /headers/x_robots_tag_noindex or /headers/x_robots_tag_nofollow
    if grep -qi "/headers/x_robots_tag_" "$TARGET_FILE"; then
        HAS_TARGET_URLS="true"
    fi
    
    # Copy file to tmp for python verifier to analyze safely
    cp "$TARGET_FILE" /tmp/x_robots_export_copy.csv
fi

# Get window info
WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "screaming frog\|seo spider" | head -1 | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "row_count": $ROW_COUNT,
    "has_x_robots_header_grep": $HAS_X_ROBOTS_HEADER,
    "has_target_urls_grep": $HAS_TARGET_URLS,
    "window_info": "$WINDOW_INFO",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="