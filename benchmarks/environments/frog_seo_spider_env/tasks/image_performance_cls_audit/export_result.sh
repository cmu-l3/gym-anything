#!/bin/bash
# Export script for Image Performance Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Image Performance Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Expected files
MISSING_DIMS_FILE="$EXPORT_DIR/missing_dimensions.csv"
HEAVY_IMAGES_FILE="$EXPORT_DIR/heavy_images.csv"
REPORT_FILE="$REPORTS_DIR/image_optimization_report.txt"

# Initialize verification vars
MISSING_DIMS_EXISTS="false"
MISSING_DIMS_VALID="false"
MISSING_DIMS_ROWS=0
HEAVY_IMAGES_EXISTS="false"
HEAVY_IMAGES_VALID="false"
HEAVY_IMAGES_ROWS=0
REPORT_EXISTS="false"
REPORT_CONTENT_VALID="false"
REPORT_SIZE=0
SF_RUNNING="false"

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Function to check if file was modified after task start
was_modified_after_start() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        echo "false"
        return
    fi
    local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
    if [ "$mtime" -gt "$TASK_START_EPOCH" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# --- Check Missing Dimensions CSV ---
if [ "$(was_modified_after_start "$MISSING_DIMS_FILE")" == "true" ]; then
    MISSING_DIMS_EXISTS="true"
    # Check for image extensions and crawler-test domain
    if grep -qi "crawler-test" "$MISSING_DIMS_FILE" && grep -qiE "\.jpg|\.png|\.gif|\.webp" "$MISSING_DIMS_FILE"; then
        MISSING_DIMS_VALID="true"
        # Count rows (excluding header)
        MISSING_DIMS_ROWS=$(($(wc -l < "$MISSING_DIMS_FILE") - 1))
    fi
fi

# --- Check Heavy Images CSV ---
if [ "$(was_modified_after_start "$HEAVY_IMAGES_FILE")" == "true" ]; then
    HEAVY_IMAGES_EXISTS="true"
    if grep -qi "crawler-test" "$HEAVY_IMAGES_FILE" && grep -qiE "\.jpg|\.png|\.gif|\.webp" "$HEAVY_IMAGES_FILE"; then
        HEAVY_IMAGES_VALID="true"
        HEAVY_IMAGES_ROWS=$(($(wc -l < "$HEAVY_IMAGES_FILE") - 1))
    fi
fi

# --- Check Files Are Distinct ---
FILES_DISTINCT="true"
if [ "$MISSING_DIMS_VALID" == "true" ] && [ "$HEAVY_IMAGES_VALID" == "true" ]; then
    # Simple check: compare row counts or checksums
    MD5_1=$(md5sum "$MISSING_DIMS_FILE" | cut -d' ' -f1)
    MD5_2=$(md5sum "$HEAVY_IMAGES_FILE" | cut -d' ' -f1)
    if [ "$MD5_1" == "$MD5_2" ]; then
        FILES_DISTINCT="false"
    fi
fi

# --- Check Report ---
if [ "$(was_modified_after_start "$REPORT_FILE")" == "true" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    # Check for keywords
    if grep -qiE "width|height|attribute|optimize|compress|kb|mb|cls" "$REPORT_FILE"; then
        REPORT_CONTENT_VALID="true"
    fi
fi

# Capture Window Title for domain verification
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 | sed 's/"/\\"/g')

# Write result JSON
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "window_info": "$WINDOW_INFO",
    "missing_dims_exists": $MISSING_DIMS_EXISTS,
    "missing_dims_valid": $MISSING_DIMS_VALID,
    "missing_dims_rows": $MISSING_DIMS_ROWS,
    "heavy_images_exists": $HEAVY_IMAGES_EXISTS,
    "heavy_images_valid": $HEAVY_IMAGES_VALID,
    "heavy_images_rows": $HEAVY_IMAGES_ROWS,
    "files_distinct": $FILES_DISTINCT,
    "report_exists": $REPORT_EXISTS,
    "report_content_valid": $REPORT_CONTENT_VALID,
    "report_size": $REPORT_SIZE,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="