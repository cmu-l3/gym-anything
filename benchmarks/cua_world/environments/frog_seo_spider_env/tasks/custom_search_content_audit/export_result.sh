#!/bin/bash
# Export result script for Custom Search Content Audit
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom Search Audit Result ==="

# 1. Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Gather State Variables
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV_NAME="custom_search_results.csv"
EXPECTED_REPORT_NAME="content_quality_report.txt"

# 3. Check CSV Export
CSV_FOUND="false"
CSV_PATH=""
CSV_ROWS=0
CSV_CREATED_DURING_TASK="false"
CSV_HAS_CUSTOM_COLS="false"

# Look for the specific filename first, then fallback to newest CSV
TARGET_CSV="$EXPORT_DIR/$EXPECTED_CSV_NAME"
CANDIDATE_CSV=""

if [ -f "$TARGET_CSV" ]; then
    CANDIDATE_CSV="$TARGET_CSV"
else
    # Fallback to newest CSV in folder
    CANDIDATE_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)
fi

if [ -n "$CANDIDATE_CSV" ] && [ -f "$CANDIDATE_CSV" ]; then
    CSV_FOUND="true"
    CSV_PATH="$CANDIDATE_CSV"
    
    # Check creation time
    FILE_EPOCH=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi

    # Count rows (header is row 1)
    TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))

    # Check for Custom Search indicators in header
    # Headers usually contain the Rule Name or "Contains"
    HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "Contains\|Does Not Contain\|Buy Button\|Availability\|Price Format"; then
        CSV_HAS_CUSTOM_COLS="true"
    fi

    # Make a copy for verifier to pull
    cp "$CSV_PATH" /tmp/verify_custom_search.csv
fi

# 4. Check Text Report
REPORT_FOUND="false"
REPORT_PATH=""
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"

TARGET_REPORT="$REPORTS_DIR/$EXPECTED_REPORT_NAME"
if [ -f "$TARGET_REPORT" ]; then
    REPORT_FOUND="true"
    REPORT_PATH="$TARGET_REPORT"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi

    # Make a copy for verifier
    cp "$REPORT_PATH" /tmp/verify_report.txt
fi

# 5. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 6. Generate JSON Result
# Using python for reliable JSON formatting
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "csv_found": "$CSV_FOUND" == "true",
    "csv_path": "$CSV_PATH",
    "csv_rows": $CSV_ROWS,
    "csv_created_during_task": "$CSV_CREATED_DURING_TASK" == "true",
    "csv_has_custom_cols": "$CSV_HAS_CUSTOM_COLS" == "true",
    "report_found": "$REPORT_FOUND" == "true",
    "report_path": "$REPORT_PATH",
    "report_size": $REPORT_SIZE,
    "report_created_during_task": "$REPORT_CREATED_DURING_TASK" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="