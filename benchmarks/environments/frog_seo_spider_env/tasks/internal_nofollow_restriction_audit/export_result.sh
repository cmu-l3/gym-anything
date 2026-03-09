#!/bin/bash
# Export script for Internal Nofollow Restriction Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

# Capture final state
take_screenshot /tmp/task_final.png

# Configuration
CSV_PATH="/home/ga/Documents/SEO/exports/internal_nofollow_report.csv"
REPORT_PATH="/home/ga/Documents/SEO/reports/nofollow_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# --- Analyze CSV File ---
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_HAS_HEADERS="false"
CSV_HAS_DATA="false"
CSV_ROW_COUNT=0
CSV_HEADERS=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi

    # Read content
    CSV_HEADERS=$(head -1 "$CSV_PATH" 2>/dev/null)
    
    # Check for Link Export headers (Source, Destination)
    if echo "$CSV_HEADERS" | grep -qi "Source" && echo "$CSV_HEADERS" | grep -qi "Destination"; then
        CSV_HAS_HEADERS="true"
    fi

    # Check for actual data (crawler-test.com URLs)
    if grep -qi "crawler-test.com" "$CSV_PATH"; then
        CSV_HAS_DATA="true"
    fi

    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$TOTAL_LINES" -gt 0 ]; then
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    fi
fi

# --- Analyze Report File ---
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT_LENGTH=0
REPORT_HAS_NUMBERS="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi

    REPORT_CONTENT_LENGTH=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check for digits (counts)
    if grep -qE "[0-9]+" "$REPORT_PATH"; then
        REPORT_HAS_NUMBERS="true"
    fi
fi

# --- Check App State ---
APP_RUNNING="false"
if is_screamingfrog_running; then
    APP_RUNNING="true"
fi

# Write JSON result
python3 << PYEOF
import json
import os

result = {
    "app_running": $APP_RUNNING == "true",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_created_during_task": "$CSV_CREATED_DURING_TASK" == "true",
    "csv_has_correct_headers": "$CSV_HAS_HEADERS" == "true",
    "csv_has_target_data": "$CSV_HAS_DATA" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_headers_preview": """$CSV_HEADERS""",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_created_during_task": "$REPORT_CREATED_DURING_TASK" == "true",
    "report_length": $REPORT_CONTENT_LENGTH,
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json