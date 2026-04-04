#!/bin/bash
# Export script for Robots Directives & Indexability Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Robots Directives Audit Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Gather environment variables & paths
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/indexability_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Analyze Exported CSV (Directives)
# We look for a CSV created AFTER task start that contains Directive-specific headers
DIRECTIVES_CSV=""
CSV_HAS_DOMAIN="false"
CSV_HAS_DIRECTIVE_COLS="false"
CSV_ROW_COUNT=0
CSV_CREATED="false"

if [ -d "$EXPORT_DIR" ]; then
    # Iterate through CSVs
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Check freshness
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            CSV_CREATED="true"
            
            # Read header and sample data
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            # Read a few lines to check for domain
            CONTENT_SAMPLE=$(head -20 "$csv_file" 2>/dev/null || echo "")
            
            # Check for Directive-specific columns
            # Directives tab exports usually have "Meta Robots 1", "X-Robots-Tag 1", "Canonical Link Element 1"
            # OR just "Meta Robots", "X-Robots-Tag" depending on export mode
            if echo "$HEADER" | grep -qi "Meta Robots\|X-Robots-Tag\|Canonical Link\|Indexability"; then
                DIRECTIVES_CSV="$csv_file"
                CSV_HAS_DIRECTIVE_COLS="true"
                
                # Check for target domain in content
                if echo "$CONTENT_SAMPLE" | grep -qi "crawler-test.com"; then
                    CSV_HAS_DOMAIN="true"
                fi
                
                # Count data rows (lines - 1)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CSV_ROW_COUNT=$((TOTAL_LINES - 1))
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 4. Analyze Text Report
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_SIZE=0
REPORT_CONTENT_CHECK="false"
REPORT_HAS_NUMBERS="false"
REPORT_HAS_URLS="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_DURING="true"
    fi
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check content quality
    REPORT_TEXT=$(cat "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
    
    # Check for keywords
    if echo "$REPORT_TEXT" | grep -qE "noindex|canonical|blocked|robots|indexable"; then
        REPORT_CONTENT_CHECK="true"
    fi
    
    # Check for numbers (counts)
    if echo "$REPORT_TEXT" | grep -qE "[0-9]+"; then
        REPORT_HAS_NUMBERS="true"
    fi
    
    # Check for URLs (looking for http/https or .com)
    if echo "$REPORT_TEXT" | grep -qE "http|https|crawler-test\.com"; then
        REPORT_HAS_URLS="true"
    fi
fi

# 5. Check SF Status
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 6. Create Result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "csv_created": "$CSV_CREATED" == "true",
    "directives_csv_found": len("$DIRECTIVES_CSV") > 0,
    "directives_csv_path": "$DIRECTIVES_CSV",
    "csv_has_domain": "$CSV_HAS_DOMAIN" == "true",
    "csv_has_directive_cols": "$CSV_HAS_DIRECTIVE_COLS" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_created_during": "$REPORT_CREATED_DURING" == "true",
    "report_size": $REPORT_SIZE,
    "report_has_keywords": "$REPORT_CONTENT_CHECK" == "true",
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "report_has_urls": "$REPORT_HAS_URLS" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result saved to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="