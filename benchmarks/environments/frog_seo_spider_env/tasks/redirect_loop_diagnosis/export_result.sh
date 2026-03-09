#!/bin/bash
# Export script for Redirect Loop Diagnosis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Redirect Loop Diagnosis Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV="$EXPORT_DIR/redirect_loops.csv"
EXPECTED_REPORT="$REPORTS_DIR/loop_analysis.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Variables to track result state
CSV_EXISTS="false"
CSV_MODIFIED_AFTER_START="false"
CSV_HAS_LOOP_DATA="false"
CSV_ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_MODIFIED_AFTER_START="false"
REPORT_CONTENT_LENGTH=0
SF_RUNNING="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Check CSV File
if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_AFTER_START="true"
        
        # Check content for loop indicators
        # crawler-test.com specific indicators: "loop_to_self", "loop_to_other"
        # SF specific indicators: "Redirect Loop", "Exceeded Max Redirects"
        if grep -qi "loop\|Exceeded Max Redirects" "$EXPECTED_CSV"; then
            CSV_HAS_LOOP_DATA="true"
        fi
        
        # Count rows (header is 1)
        TOTAL_LINES=$(wc -l < "$EXPECTED_CSV" 2>/dev/null || echo "0")
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
        
        # Copy for verifier
        cp "$EXPECTED_CSV" /tmp/redirect_loops_export.csv 2>/dev/null || true
    fi
fi

# Check Report File
if [ -f "$EXPECTED_REPORT" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_REPORT" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_AFTER_START="true"
        REPORT_CONTENT_LENGTH=$(stat -c %s "$EXPECTED_REPORT" 2>/dev/null || echo "0")
        
        # Copy for verifier
        cp "$EXPECTED_REPORT" /tmp/loop_analysis_report.txt 2>/dev/null || true
    fi
fi

# Get window info for verification context
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Write result JSON using Python for safety
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_modified": "$CSV_MODIFIED_AFTER_START" == "true",
    "csv_has_loop_data": "$CSV_HAS_LOOP_DATA" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_modified": "$REPORT_MODIFIED_AFTER_START" == "true",
    "report_length": $REPORT_CONTENT_LENGTH,
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/redirect_loop_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/redirect_loop_result.json")
PYEOF

echo "=== Export Complete ==="