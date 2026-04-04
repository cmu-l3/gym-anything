#!/bin/bash
# Export script for Shortest Crawl Path Diagnosis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

# Paths
EXPORT_PATH="/home/ga/Documents/SEO/exports/himalayas_path.csv"
REPORT_PATH="/home/ga/Documents/SEO/reports/depth_value.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check CSV Export
CSV_EXISTS="false"
CSV_MODIFIED_IN_TASK="false"
CSV_HAS_TARGET="false"
CSV_ROW_COUNT=0

if [ -f "$EXPORT_PATH" ]; then
    CSV_EXISTS="true"
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_IN_TASK="true"
    fi
    
    # Check content for target fragment
    if grep -q "its-only-the-himalayas_981" "$EXPORT_PATH"; then
        CSV_HAS_TARGET="true"
    fi
    
    # Count rows (excluding header)
    CSV_ROW_COUNT=$(grep -cve '^\s*$' "$EXPORT_PATH") 
fi

# 3. Check Depth Report
REPORT_EXISTS="false"
REPORT_MODIFIED_IN_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_IN_TASK="true"
    fi
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr -d '[:space:]')
fi

# 4. Check SF Status
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 5. Generate JSON Result
# Use python for robust JSON generation
python3 << PYEOF
import json

result = {
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_modified_in_task": "$CSV_MODIFIED_IN_TASK" == "true",
    "csv_has_target": "$CSV_HAS_TARGET" == "true",
    "csv_row_count": int("$CSV_ROW_COUNT"),
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_modified_in_task": "$REPORT_MODIFIED_IN_TASK" == "true",
    "report_content": "$REPORT_CONTENT",
    "sf_running": "$SF_RUNNING" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="