#!/bin/bash
# Export script for Broken Image Asset Audit
# Runs inside the container after the agent finishes

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture Final State
# Screenshot is critical for VLM verification of UI state
take_screenshot /tmp/task_final.png

# 2. Collect Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/SEO/exports"

# 3. Analyze Exported Files
# We look for a CSV file created AFTER task start containing "broken_images" in name
# If specific name not found, we look for ANY new CSV and check content

TARGET_FILE=""
FILE_CREATED="false"
IS_IMAGE_REPORT="false"
HAS_4XX_ERRORS="false"
ROW_COUNT=0
FOUND_CRAWLER_TEST="false"

# Find newest CSV in export dir
NEWEST_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -n 1)

if [ -f "$NEWEST_CSV" ]; then
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$NEWEST_CSV")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED="true"
        TARGET_FILE="$NEWEST_CSV"
        
        # Analyze Content
        # Check row count (subtract header)
        TOTAL_LINES=$(wc -l < "$NEWEST_CSV")
        ROW_COUNT=$((TOTAL_LINES - 1))
        
        # Check for Image Indicators (extensions or MIME types)
        if grep -qiE "\.jpg|\.jpeg|\.png|\.gif|\.webp|image/" "$NEWEST_CSV"; then
            IS_IMAGE_REPORT="true"
        fi
        
        # Check for 4xx Errors (404, Client Error)
        if grep -qiE "404|403|Client Error" "$NEWEST_CSV"; then
            HAS_4XX_ERRORS="true"
        fi
        
        # Check for correct domain
        if grep -qi "crawler-test.com" "$NEWEST_CSV"; then
            FOUND_CRAWLER_TEST="true"
        fi
        
        # Make a copy for verifier to read easily
        cp "$NEWEST_CSV" /tmp/analyzed_export.csv
    fi
fi

# 4. Check Application State
APP_RUNNING="false"
if is_screamingfrog_running; then
    APP_RUNNING="true"
fi

# Get Window Title for extra context (e.g. "Screaming Frog - crawler-test.com")
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep -i "Screaming Frog" | head -n 1 | cut -d' ' -f5- || echo "")

# 5. Create JSON Result
# Using python for safe JSON formatting
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'file_created': $FILE_CREATED == 1, # boolean conversion
    'target_file': '$TARGET_FILE',
    'is_image_report': $IS_IMAGE_REPORT == 1,
    'has_4xx_errors': $HAS_4XX_ERRORS == 1,
    'found_crawler_test': $FOUND_CRAWLER_TEST == 1,
    'row_count': $ROW_COUNT,
    'app_running': $APP_RUNNING == 1,
    'window_title': '''$WINDOW_TITLE''',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so host can copy
chmod 666 /tmp/task_result.json 2>/dev/null || true
if [ -f /tmp/analyzed_export.csv ]; then
    chmod 666 /tmp/analyzed_export.csv 2>/dev/null || true
fi

echo "=== Export Complete ==="
cat /tmp/task_result.json