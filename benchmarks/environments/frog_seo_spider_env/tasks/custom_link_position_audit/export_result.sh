#!/bin/bash
# Export script for Custom Link Position Audit

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Define Paths
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_DIR="/home/ga/Documents/SEO/reports"
CSV_FILE="$EXPORT_DIR/inlinks_by_position.csv"
REPORT_FILE="$REPORT_DIR/link_distribution_report.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 3. Analyze CSV Export
CSV_EXISTS="false"
CSV_VALID="false"
HAS_POSITION_COL="false"
FOUND_HEADER="false"
FOUND_FOOTER="false"
FOUND_SIDEBAR="false"
FOUND_MAIN="false"
ROW_COUNT=0
DOMAIN_MATCH="false"

if [ -f "$CSV_FILE" ]; then
    FILE_TIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    
    # Check if created after task start
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        
        # Check for meaningful content
        ROW_COUNT=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
        if [ "$ROW_COUNT" -gt 5 ]; then
            CSV_VALID="true"
        fi
        
        # Read header and sample data
        HEADER=$(head -n 1 "$CSV_FILE")
        # Check for "Link Position" column (standard name in SF export)
        if echo "$HEADER" | grep -qi "Link Position"; then
            HAS_POSITION_COL="true"
        fi
        
        # Check for specific custom values in the file
        # using grep to search the whole file is faster/easier than parsing column specifically in bash
        if grep -q "Header" "$CSV_FILE"; then FOUND_HEADER="true"; fi
        if grep -q "Footer" "$CSV_FILE"; then FOUND_FOOTER="true"; fi
        if grep -q "Sidebar" "$CSV_FILE"; then FOUND_SIDEBAR="true"; fi
        if grep -q "Main_Content" "$CSV_FILE"; then FOUND_MAIN="true"; fi
        
        # Check if correct domain was crawled
        if grep -q "books.toscrape.com" "$CSV_FILE"; then
            DOMAIN_MATCH="true"
        fi
    fi
else
    # Fallback: Check if they named it something slightly different but valid
    # Find newest CSV in directory
    LATEST_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -n 1)
    if [ -n "$LATEST_CSV" ]; then
        FILE_TIME=$(stat -c %Y "$LATEST_CSV" 2>/dev/null || echo "0")
        if [ "$FILE_TIME" -gt "$TASK_START" ]; then
            # We found a candidate, let's analyze it loosely
            if grep -q "Main_Content" "$LATEST_CSV" || grep -q "Sidebar" "$LATEST_CSV"; then
                # It looks like the right file even if named wrong
                CSV_EXISTS="true"
                CSV_FILE="$LATEST_CSV" # update reference
                ROW_COUNT=$(wc -l < "$CSV_FILE")
                CSV_VALID="true" # Assuming valid if it has our custom tags
                if grep -qi "Link Position" "$LATEST_CSV"; then HAS_POSITION_COL="true"; fi
                if grep -q "Header" "$CSV_FILE"; then FOUND_HEADER="true"; fi
                if grep -q "Footer" "$CSV_FILE"; then FOUND_FOOTER="true"; fi
                if grep -q "Sidebar" "$CSV_FILE"; then FOUND_SIDEBAR="true"; fi
                if grep -q "Main_Content" "$CSV_FILE"; then FOUND_MAIN="true"; fi
                if grep -q "books.toscrape.com" "$CSV_FILE"; then DOMAIN_MATCH="true"; fi
            fi
        fi
    fi
fi

# 4. Analyze Text Report
REPORT_EXISTS="false"
REPORT_CONTENT_VALID="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_TIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        # Check if it contains our keywords and some numbers
        if grep -qE "Header|Footer|Sidebar|Main_Content" "$REPORT_FILE" && grep -qE "[0-9]+" "$REPORT_FILE"; then
            REPORT_CONTENT_VALID="true"
        fi
    fi
fi

# 5. Check App Status
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 6. Generate JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "sf_running": $SF_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "has_position_col": $HAS_POSITION_COL,
    "found_header": $FOUND_HEADER,
    "found_footer": $FOUND_FOOTER,
    "found_sidebar": $FOUND_SIDEBAR,
    "found_main": $FOUND_MAIN,
    "domain_match": $DOMAIN_MATCH,
    "row_count": $ROW_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_content_valid": $REPORT_CONTENT_VALID,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Save Result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="