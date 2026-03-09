#!/bin/bash
# Export result script for Page Performance Audit task

# Ensure script continues even if some commands fail
set +e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Page Performance Audit Result ==="

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Basic Variables
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/performance_report.txt"

# 3. Check Application State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi
# Get window title to verify target domain was crawled/visible
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 4. Analyze Exported CSVs
# We look for a CSV created AFTER task start that contains performance columns
PERF_CSV_FOUND="false"
PERF_CSV_PATH=""
CSV_HAS_RESPONSE_TIME="false"
CSV_HAS_SIZE="false"
CSV_HAS_WORD_COUNT="false"
CSV_ROW_COUNT=0
TARGET_DOMAIN_IN_CSV="false"

# Iterate through CSVs in export dir
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        # Check creation/mod time
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Read header
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            # Read a few rows for content check
            SAMPLE=$(head -20 "$csv_file" 2>/dev/null || echo "")
            
            # Check for required columns (case insensitive)
            HAS_TIME=$(echo "$HEADER" | grep -qi "Response Time" && echo "true" || echo "false")
            HAS_SIZE=$(echo "$HEADER" | grep -qi "Size" && echo "true" || echo "false")
            HAS_WORDS=$(echo "$HEADER" | grep -qi "Word Count" && echo "true" || echo "false")
            
            # If it looks like a performance export
            if [ "$HAS_TIME" = "true" ] || [ "$HAS_SIZE" = "true" ]; then
                PERF_CSV_FOUND="true"
                PERF_CSV_PATH="$csv_file"
                CSV_HAS_RESPONSE_TIME="$HAS_TIME"
                CSV_HAS_SIZE="$HAS_SIZE"
                CSV_HAS_WORD_COUNT="$HAS_WORDS"
                
                # Count data rows (lines - 1)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "0")
                if [ "$TOTAL_LINES" -gt 0 ]; then
                    CSV_ROW_COUNT=$((TOTAL_LINES - 1))
                fi
                
                # Check for target domain
                if echo "$SAMPLE" | grep -qi "books.toscrape.com"; then
                    TARGET_DOMAIN_IN_CSV="true"
                fi
                
                # If we found a good candidate, break (assuming mostly one main export)
                break
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 5. Analyze the Text Report
REPORT_FOUND="false"
REPORT_LENGTH=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_TARGET_URL="false"
REPORT_HAS_KEYWORDS="false"

if [ -f "$REPORT_PATH" ]; then
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_FOUND="true"
        REPORT_LENGTH=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        
        CONTENT=$(cat "$REPORT_PATH")
        
        # Check for numbers (performance metrics)
        if echo "$CONTENT" | grep -qE "[0-9]+"; then
            REPORT_HAS_NUMBERS="true"
        fi
        
        # Check for target URL mentions
        if echo "$CONTENT" | grep -qi "books.toscrape.com"; then
            REPORT_HAS_TARGET_URL="true"
        fi
        
        # Check for performance keywords
        if echo "$CONTENT" | grep -qiE "slow|fast|large|size|kb|mb|ms|seconds|recommend|improve"; then
            REPORT_HAS_KEYWORDS="true"
        fi
    fi
fi

# 6. Create JSON Result
# Use python to safely dump JSON avoids shell quoting hell
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_found": "$PERF_CSV_FOUND" == "true",
    "csv_path": "$PERF_CSV_PATH",
    "csv_has_response_time": "$CSV_HAS_RESPONSE_TIME" == "true",
    "csv_has_size": "$CSV_HAS_SIZE" == "true",
    "csv_has_word_count": "$CSV_HAS_WORD_COUNT" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_target_domain": "$TARGET_DOMAIN_IN_CSV" == "true",
    "report_found": "$REPORT_FOUND" == "true",
    "report_length": $REPORT_LENGTH,
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "report_has_target_url": "$REPORT_HAS_TARGET_URL" == "true",
    "report_has_keywords": "$REPORT_HAS_KEYWORDS" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON created at /tmp/task_result.json")
PYEOF

# 7. Print result for log
cat /tmp/task_result.json

echo "=== Export Complete ==="