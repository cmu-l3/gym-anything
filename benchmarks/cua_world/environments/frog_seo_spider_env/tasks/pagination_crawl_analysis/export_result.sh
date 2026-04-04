#!/bin/bash
# Export script for Pagination Crawl Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Pagination Crawl Analysis Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/pagination_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
EXPORT_CSV=""
EXPORT_ROW_COUNT=0
PAGINATED_URL_COUNT=0
TARGET_DOMAIN_FOUND="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT_VALID="false"
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title for verification
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider\|books.toscrape" | head -1 || echo "")

# 1. Analyze Exported CSV
# Find CSV files created/modified after task start
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Found a candidate file
            
            # Check for target domain to ensure it's the right crawl
            if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                EXPORT_CSV="$csv_file"
                TARGET_DOMAIN_FOUND="true"
                
                # Count total rows (minus header)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                EXPORT_ROW_COUNT=$((TOTAL_LINES - 1))
                
                # Count paginated URLs (URLs containing /page-)
                PAGINATED_URL_COUNT=$(grep -c "/page-" "$csv_file" 2>/dev/null || echo "0")
                
                # If we found a valid file, stop looking (assuming user only exported one relevant file)
                break
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Analyze Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        
        # Check for meaningful content
        # Must contain numbers (counts) and key terms
        CONTENT=$(cat "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
        HAS_NUMBERS=$(echo "$CONTENT" | grep -qE "[0-9]+" && echo "true" || echo "false")
        HAS_KEYWORDS=$(echo "$CONTENT" | grep -qE "page|paginat|url|depth" && echo "true" || echo "false")
        
        if [ "$HAS_NUMBERS" = "true" ] && [ "$HAS_KEYWORDS" = "true" ] && [ "$REPORT_SIZE" -gt 100 ]; then
            REPORT_CONTENT_VALID="true"
        fi
    fi
fi

# Count total new CSVs (for debugging/feedback)
NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

# Write result JSON using Python for safety
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "new_csv_count": $NEW_CSV_COUNT,
    "export_csv_found": len("$EXPORT_CSV") > 0,
    "export_csv_path": "$EXPORT_CSV",
    "export_row_count": $EXPORT_ROW_COUNT,
    "paginated_url_count": $PAGINATED_URL_COUNT,
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_content_valid": "$REPORT_CONTENT_VALID" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/pagination_crawl_analysis_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/pagination_crawl_analysis_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="