#!/bin/bash
# Export script for URI Structure Hygiene Audit task
# This script gathers evidence for the python verifier

source /workspace/scripts/task_utils.sh

echo "=== Exporting URI Structure Hygiene Audit Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Define paths
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV="$EXPORT_DIR/uri_analysis.csv"
EXPECTED_REPORT="$REPORTS_DIR/url_hygiene_report.txt"

TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Check CSV File
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_ROW_COUNT=0
CSV_HAS_TARGET_DOMAIN="false"
CSV_PATH_FOR_VERIFY=""

# Check primary expected path
if [ -f "$EXPECTED_CSV" ]; then
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_EXISTS="true"
        CSV_CREATED_DURING_TASK="true"
        CSV_PATH_FOR_VERIFY="$EXPECTED_CSV"
    fi
else
    # Fallback: Check if user exported with a different name but still correct content
    # Find newest CSV in export dir
    NEWEST_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)
    if [ -n "$NEWEST_CSV" ]; then
        FILE_EPOCH=$(stat -c %Y "$NEWEST_CSV" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            CSV_EXISTS="true"
            CSV_CREATED_DURING_TASK="true"
            CSV_PATH_FOR_VERIFY="$NEWEST_CSV"
            echo "Found alternative CSV created during task: $NEWEST_CSV"
        fi
    fi
fi

if [ "$CSV_EXISTS" = "true" ]; then
    # Analyze CSV content lightly (Python verifier does deep check)
    CSV_ROW_COUNT=$(wc -l < "$CSV_PATH_FOR_VERIFY" || echo "0")
    # Subtract header
    CSV_ROW_COUNT=$((CSV_ROW_COUNT - 1))
    
    if grep -qi "crawler-test.com" "$CSV_PATH_FOR_VERIFY"; then
        CSV_HAS_TARGET_DOMAIN="true"
    fi
    
    # Copy for verifier access
    cp "$CSV_PATH_FOR_VERIFY" /tmp/verify_uri_export.csv
    chmod 644 /tmp/verify_uri_export.csv
fi

# 4. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0
REPORT_PATH_FOR_VERIFY=""

if [ -f "$EXPECTED_REPORT" ]; then
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_REPORT" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_CREATED_DURING_TASK="true"
        REPORT_PATH_FOR_VERIFY="$EXPECTED_REPORT"
    fi
fi

if [ "$REPORT_EXISTS" = "true" ]; then
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH_FOR_VERIFY" || echo "0")
    # Copy for verifier access
    cp "$REPORT_PATH_FOR_VERIFY" /tmp/verify_report.txt
    chmod 644 /tmp/verify_report.txt
fi

# 5. Check System State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 6. Create JSON Result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_created_during_task": "$CSV_CREATED_DURING_TASK" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_target_domain": "$CSV_HAS_TARGET_DOMAIN" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_created_during_task": "$REPORT_CREATED_DURING_TASK" == "true",
    "report_size": $REPORT_SIZE,
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="