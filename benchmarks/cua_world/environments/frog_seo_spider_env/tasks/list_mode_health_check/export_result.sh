#!/bin/bash
# Export script for List Mode Health Check task

source /workspace/scripts/task_utils.sh

echo "=== Exporting List Mode Health Check Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/landing_page_health.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
URL_LIST_FILE="/home/ga/Documents/SEO/landing_pages.txt"

# Initialize variables
SF_RUNNING="false"
CSV_FOUND="false"
CSV_PATH=""
CSV_ROW_COUNT=0
URLS_MATCHED_COUNT=0
HAS_SEO_COLUMNS="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_CONTENT="false"

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 1. Analyze CSV Export
# Find the newest CSV file created after task start
if [ -d "$EXPORT_DIR" ]; then
    # Find files modified after task start
    NEWEST_CSV=$(find "$EXPORT_DIR" -name "*.csv" -newermt "@$TASK_START_EPOCH" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$NEWEST_CSV" ]; then
        CSV_FOUND="true"
        CSV_PATH="$NEWEST_CSV"
        
        # Count data rows (excluding header)
        TOTAL_LINES=$(wc -l < "$NEWEST_CSV" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            CSV_ROW_COUNT=$((TOTAL_LINES - 1))
        fi

        # Check for SEO columns (Title, Meta Description, Status Code)
        HEADER=$(head -1 "$NEWEST_CSV" 2>/dev/null || echo "")
        if echo "$HEADER" | grep -qi "Title" && echo "$HEADER" | grep -qi "Status Code"; then
            HAS_SEO_COLUMNS="true"
        fi

        # Check for matching URLs from the input list
        # We check 5 random URLs from the input list to verify they exist in the export
        MATCHES=0
        TEST_URLS=$(shuf -n 5 "$URL_LIST_FILE" 2>/dev/null || head -5 "$URL_LIST_FILE")
        
        while IFS= read -r url; do
            # Grep logic: remove protocol/www variations to match easier if needed, 
            # but SF usually exports full URLs.
            if grep -Fq "$url" "$NEWEST_CSV"; then
                MATCHES=$((MATCHES + 1))
            fi
        done <<< "$TEST_URLS"
        
        URLS_MATCHED_COUNT=$MATCHES
        
        # Also check if it's a "list mode" export vs "spider mode"
        # List mode on 20 URLs should produce ~20 rows. Spider mode on books.toscrape.com produces ~1000.
        # We rely on CSV_ROW_COUNT in verifier.
    fi
fi

# 2. Analyze Text Report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check for meaningful content
    if [ "$REPORT_SIZE" -gt 50 ]; then
        if grep -qiE "status|title|missing|error|ok|200|404|found" "$REPORT_PATH"; then
            REPORT_HAS_CONTENT="true"
        fi
    fi
fi

# Write result JSON using Python
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "csv_found": "$CSV_FOUND" == "true",
    "csv_path": "$CSV_PATH",
    "csv_row_count": $CSV_ROW_COUNT,
    "has_seo_columns": "$HAS_SEO_COLUMNS" == "true",
    "urls_matched_count": $URLS_MATCHED_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size": $REPORT_SIZE,
    "report_has_content": "$REPORT_HAS_CONTENT" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/list_mode_health_check_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/list_mode_health_check_result.json")
PYEOF

echo "=== Export Complete ==="