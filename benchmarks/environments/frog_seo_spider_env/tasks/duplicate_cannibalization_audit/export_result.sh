#!/bin/bash
# Export script for Duplicate Cannibalization Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Duplicate Cannibalization Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TITLES_FILE="$EXPORT_DIR/duplicate_titles.csv"
H1S_FILE="$EXPORT_DIR/duplicate_h1s.csv"
REPORT_FILE="$REPORTS_DIR/cannibalization_report.txt"

TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
TITLES_EXISTS="false"
TITLES_VALID="false"
TITLES_ROW_COUNT=0
H1S_EXISTS="false"
H1S_VALID="false"
H1S_ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_SIZE=0
SF_RUNNING="false"

# Check if Screaming Frog is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 1. Verify Duplicate Titles CSV
if [ -f "$TITLES_FILE" ]; then
    FILE_EPOCH=$(stat -c %Y "$TITLES_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        TITLES_EXISTS="true"
        # Check content: header should contain "Title" and "Address"
        HEADER=$(head -1 "$TITLES_FILE" 2>/dev/null || echo "")
        if echo "$HEADER" | grep -qi "Title"; then
            TITLES_VALID="true"
            # Count rows (minus header)
            TOTAL_LINES=$(wc -l < "$TITLES_FILE" 2>/dev/null || echo "1")
            TITLES_ROW_COUNT=$((TOTAL_LINES - 1))
            
            # Prepare for verifier to inspect content deeply
            cp "$TITLES_FILE" /tmp/verify_titles.csv
        fi
    fi
fi

# 2. Verify Duplicate H1s CSV
if [ -f "$H1S_FILE" ]; then
    FILE_EPOCH=$(stat -c %Y "$H1S_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        H1S_EXISTS="true"
        # Check content: header should contain "H1"
        HEADER=$(head -1 "$H1S_FILE" 2>/dev/null || echo "")
        if echo "$HEADER" | grep -qi "H1"; then
            H1S_VALID="true"
            TOTAL_LINES=$(wc -l < "$H1S_FILE" 2>/dev/null || echo "1")
            H1S_ROW_COUNT=$((TOTAL_LINES - 1))
            
            # Prepare for verifier
            cp "$H1S_FILE" /tmp/verify_h1s.csv
        fi
    fi
fi

# 3. Verify Report
if [ -f "$REPORT_FILE" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
        if [ "$REPORT_SIZE" -ge 400 ]; then
            REPORT_VALID="true"
        fi
        
        # Prepare for verifier
        cp "$REPORT_FILE" /tmp/verify_report.txt
    fi
fi

# Create JSON result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "titles_file": {
        "exists": "$TITLES_EXISTS" == "true",
        "valid_structure": "$TITLES_VALID" == "true",
        "row_count": $TITLES_ROW_COUNT
    },
    "h1s_file": {
        "exists": "$H1S_EXISTS" == "true",
        "valid_structure": "$H1S_VALID" == "true",
        "row_count": $H1S_ROW_COUNT
    },
    "report_file": {
        "exists": "$REPORT_EXISTS" == "true",
        "valid_length": "$REPORT_VALID" == "true",
        "size_bytes": $REPORT_SIZE
    },
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result saved to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="