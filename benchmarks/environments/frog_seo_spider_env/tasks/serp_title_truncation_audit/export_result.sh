#!/bin/bash
# Export script for SERP Title Pixel Width Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting SERP Title Truncation Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Expected files
EXPECTED_CSV="$EXPORT_DIR/page_titles_serp.csv"
EXPECTED_REPORT="$REPORTS_DIR/title_truncation_report.txt"

# --- CSV Analysis ---
CSV_EXISTS="false"
CSV_MODIFIED_AFTER_START="false"
CSV_ROW_COUNT=0
CSV_HAS_TARGET_DOMAIN="false"
CSV_HAS_TITLE_COL="false"
CSV_HAS_PIXEL_WIDTH_COL="false"

if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_AFTER_START="true"
    fi

    # Check content
    HEADER=$(head -1 "$EXPECTED_CSV" 2>/dev/null || echo "")
    
    # Check for domain
    if grep -qi "books.toscrape.com" "$EXPECTED_CSV" 2>/dev/null; then
        CSV_HAS_TARGET_DOMAIN="true"
    fi

    # Check for Title column
    if echo "$HEADER" | grep -qi "Title 1\|Title"; then
        CSV_HAS_TITLE_COL="true"
    fi

    # Check for Pixel Width column (Critical for this task)
    if echo "$HEADER" | grep -qi "Pixel Width"; then
        CSV_HAS_PIXEL_WIDTH_COL="true"
    fi

    # Count rows (minus header)
    TOTAL_LINES=$(wc -l < "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$TOTAL_LINES" -gt 0 ]; then
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    fi
fi

# --- Report Analysis ---
REPORT_EXISTS="false"
REPORT_MODIFIED_AFTER_START="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_KEYWORD_TRUNCATION="false"
REPORT_HAS_KEYWORD_PIXEL="false"
REPORT_HAS_RECOMMENDATION="false"

if [ -f "$EXPECTED_REPORT" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_REPORT" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_AFTER_START="true"
    fi
    REPORT_SIZE=$(stat -c %s "$EXPECTED_REPORT" 2>/dev/null || echo "0")

    # Content checks using grep
    # Check for at least 3 numbers (counts, pixels, etc)
    NUM_COUNT=$(grep -oE "[0-9]+" "$EXPECTED_REPORT" | wc -l)
    if [ "$NUM_COUNT" -ge 3 ]; then
        REPORT_HAS_NUMBERS="true"
    fi

    if grep -qi "truncat" "$EXPECTED_REPORT"; then
        REPORT_HAS_KEYWORD_TRUNCATION="true"
    fi

    if grep -qi "pixel\|width" "$EXPECTED_REPORT"; then
        REPORT_HAS_KEYWORD_PIXEL="true"
    fi

    if grep -qiE "recommend|suggest|should|shorten|reduce|rewrite" "$EXPECTED_REPORT"; then
        REPORT_HAS_RECOMMENDATION="true"
    fi
fi

# Check if SF is running
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Write result JSON using Python for safe serialization
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_modified_after_start": "$CSV_MODIFIED_AFTER_START" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_target_domain": "$CSV_HAS_TARGET_DOMAIN" == "true",
    "csv_has_title_col": "$CSV_HAS_TITLE_COL" == "true",
    "csv_has_pixel_width_col": "$CSV_HAS_PIXEL_WIDTH_COL" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_modified_after_start": "$REPORT_MODIFIED_AFTER_START" == "true",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "report_has_keyword_truncation": "$REPORT_HAS_KEYWORD_TRUNCATION" == "true",
    "report_has_keyword_pixel": "$REPORT_HAS_KEYWORD_PIXEL" == "true",
    "report_has_recommendation": "$REPORT_HAS_RECOMMENDATION" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="