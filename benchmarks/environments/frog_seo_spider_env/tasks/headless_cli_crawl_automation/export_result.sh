#!/bin/bash
# Export script for Headless CLI Crawl Automation task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Headless CLI Crawl Result ==="

take_screenshot /tmp/task_end_screenshot.png

OUTPUT_DIR="/home/ga/Documents/SEO/cli_results"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
DIR_EXISTS="false"
FILE_FOUND="false"
FILE_PATH=""
FILE_CREATED_AFTER_START="false"
VALID_DOMAIN="false"
ROW_COUNT=0
HEADLESS_LOG_DETECTED="false"

# 1. Check if output directory exists
if [ -d "$OUTPUT_DIR" ]; then
    DIR_EXISTS="true"
    
    # 2. Look for the expected CSV file
    # Screaming Frog naming convention for "Internal:All" usually contains "internal_all"
    # But user might map it differently, so we check for any CSV
    
    # Find the most recently modified CSV in the target directory
    LATEST_CSV=$(ls -t "$OUTPUT_DIR"/*.csv 2>/dev/null | head -1)
    
    if [ -n "$LATEST_CSV" ]; then
        FILE_FOUND="true"
        FILE_PATH="$LATEST_CSV"
        
        # 3. Check modification time
        FILE_EPOCH=$(stat -c %Y "$LATEST_CSV" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            FILE_CREATED_AFTER_START="true"
        fi
        
        # 4. Check content (Domain and Rows)
        # Count rows (minus header)
        TOTAL_LINES=$(wc -l < "$LATEST_CSV" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            ROW_COUNT=$((TOTAL_LINES - 1))
        fi
        
        # Check for target domain in the file content
        if grep -q "quotes.toscrape.com" "$LATEST_CSV"; then
            VALID_DOMAIN="true"
        fi
    fi
fi

# 5. Check for CLI execution evidence
# Screaming Frog usually writes a log file in ~/.ScreamingFrogSEOSpider/spider.log
# We can check if it ran recently.
LOG_FILE="/home/ga/.ScreamingFrogSEOSpider/spider.log"
if [ -f "$LOG_FILE" ]; then
    LOG_EPOCH=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$LOG_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        # Check log for headless mode indicators
        if grep -i "Headless mode" "$LOG_FILE" 2>/dev/null; then
            HEADLESS_LOG_DETECTED="true"
        fi
    fi
fi

# Create result JSON
python3 << PYEOF
import json

result = {
    "dir_exists": "$DIR_EXISTS" == "true",
    "file_found": "$FILE_FOUND" == "true",
    "file_path": "$FILE_PATH",
    "file_created_after_start": "$FILE_CREATED_AFTER_START" == "true",
    "valid_domain": "$VALID_DOMAIN" == "true",
    "row_count": $ROW_COUNT,
    "headless_log_detected": "$HEADLESS_LOG_DETECTED" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="