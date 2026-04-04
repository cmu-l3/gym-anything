#!/bin/bash
# Export script for TTFB Bottleneck Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting TTFB Bottleneck Analysis Result ==="

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/ttfb_analysis.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. FIND THE CSV EXPORT
BEST_CSV=""
CSV_CREATED_AFTER_START="false"
CSV_HAS_RESPONSE_TIME="false"
CSV_HAS_TARGET_DOMAIN="false"
CSV_ROW_COUNT=0

# Iterate through CSVs in export dir
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Check if modified/created after task start
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            CSV_CREATED_AFTER_START="true"
            
            # Read header and first few lines
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            SAMPLE=$(head -10 "$csv_file" 2>/dev/null || echo "")
            
            # Check for Response Time column (SF names vary slightly by version/export type)
            if echo "$HEADER" | grep -qi "Response Time"; then
                CSV_HAS_RESPONSE_TIME="true"
            fi
            
            # Check for target domain
            if echo "$SAMPLE" | grep -qi "books.toscrape.com"; then
                CSV_HAS_TARGET_DOMAIN="true"
            fi
            
            # If it looks like a good candidate, keep it
            if [ "$CSV_HAS_RESPONSE_TIME" = "true" ] && [ "$CSV_HAS_TARGET_DOMAIN" = "true" ]; then
                BEST_CSV="$csv_file"
                # Count data rows (lines - 1)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CSV_ROW_COUNT=$((TOTAL_LINES - 1))
                break # Stop after finding a valid matching file
            fi
            
            # Fallback: keep the last modified CSV if we haven't found a perfect match
            if [ -z "$BEST_CSV" ]; then
                BEST_CSV="$csv_file"
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CSV_ROW_COUNT=$((TOTAL_LINES - 1))
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. CHECK THE REPORT
REPORT_EXISTS="false"
REPORT_CREATED_AFTER_START="false"
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_AFTER_START="true"
    fi
fi

# 3. CHECK APP STATUS
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 4. PREPARE EXPORT JSON
# Use Python to generate valid JSON and handle potential string escaping issues
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_path": "$BEST_CSV",
    "csv_created_after_start": "$CSV_CREATED_AFTER_START" == "true",
    "csv_has_response_time": "$CSV_HAS_RESPONSE_TIME" == "true",
    "csv_has_target_domain": "$CSV_HAS_TARGET_DOMAIN" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "report_path": "$REPORT_PATH",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_created_after_start": "$REPORT_CREATED_AFTER_START" == "true",
    "report_size": $REPORT_SIZE,
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="