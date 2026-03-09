#!/bin/bash
# Export script for Mobile User-Agent Crawl Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Mobile User-Agent Crawl Audit Result ==="

# 1. Capture Final State
take_screenshot /tmp/task_final_state.png

# 2. Variables
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_DIR="/home/ga/Documents/SEO/reports"
SF_CONFIG_FILE="/home/ga/.ScreamingFrogSEOSpider/spider.config"

# 3. Check User-Agent Configuration
# Screaming Frog saves config to disk periodically or on exit.
# We check the file. If SF is running, we might need to rely on VLM or the report,
# but often the config file updates when settings change or we can check the logs.
# For verification, we read the config file.
CURRENT_UA=$(grep "^userAgent=" "$SF_CONFIG_FILE" | cut -d'=' -f2- || echo "Unknown")
UA_IS_MOBILE="false"
if echo "$CURRENT_UA" | grep -qi "Googlebot Smartphone\|Android\|Mobile\|Smartphone"; then
    UA_IS_MOBILE="true"
fi

# 4. Find & Verify Internal HTML Export
INTERNAL_CSV=""
INTERNAL_CSV_VALID="false"
INTERNAL_ROW_COUNT=0

# Look for the specific file requested, or a recent CSV that looks like it
POSSIBLE_INTERNAL=$(find "$EXPORT_DIR" -name "*internal*.csv" -newer /tmp/task_start_time 2>/dev/null | head -1)
# Also check exact name
if [ -f "$EXPORT_DIR/mobile_internal_html.csv" ]; then
    POSSIBLE_INTERNAL="$EXPORT_DIR/mobile_internal_html.csv"
fi

if [ -f "$POSSIBLE_INTERNAL" ]; then
    INTERNAL_CSV="$POSSIBLE_INTERNAL"
    # Check content (Header should have Title, H1 etc.)
    HEADER=$(head -1 "$POSSIBLE_INTERNAL")
    if echo "$HEADER" | grep -qi "Address\|Title 1\|H1-1"; then
        # Check if contains target domain
        if grep -qi "books.toscrape.com" "$POSSIBLE_INTERNAL"; then
            INTERNAL_CSV_VALID="true"
            INTERNAL_ROW_COUNT=$(wc -l < "$POSSIBLE_INTERNAL")
            INTERNAL_ROW_COUNT=$((INTERNAL_ROW_COUNT - 1))
        fi
    fi
fi

# 5. Find & Verify Custom Extraction Export
CUSTOM_CSV=""
CUSTOM_CSV_VALID="false"
CUSTOM_HAS_VIEWPORT="false"
CUSTOM_ROW_COUNT=0

POSSIBLE_CUSTOM=$(find "$EXPORT_DIR" -name "*custom*.csv" -newer /tmp/task_start_time 2>/dev/null | head -1)
if [ -f "$EXPORT_DIR/mobile_custom_extraction.csv" ]; then
    POSSIBLE_CUSTOM="$EXPORT_DIR/mobile_custom_extraction.csv"
fi

if [ -f "$POSSIBLE_CUSTOM" ]; then
    CUSTOM_CSV="$POSSIBLE_CUSTOM"
    HEADER=$(head -1 "$POSSIBLE_CUSTOM")
    
    # Check if header contains "Viewport" or "Custom Extraction"
    if echo "$HEADER" | grep -qi "Viewport\|Custom Extraction"; then
        CUSTOM_CSV_VALID="true"
        
        # Check row count
        TOTAL_ROWS=$(wc -l < "$POSSIBLE_CUSTOM")
        CUSTOM_ROW_COUNT=$((TOTAL_ROWS - 1))
        
        # Check for extracted viewport data (meta name="viewport" usually has "width=device-width" etc.)
        # books.toscrape.com viewport tag: <meta name="viewport" content="width=device-width, initial-scale=1.0">
        if grep -qi "width=device-width" "$POSSIBLE_CUSTOM"; then
            CUSTOM_HAS_VIEWPORT="true"
        fi
    fi
fi

# 6. Verify Report
REPORT_FILE="$REPORT_DIR/mobile_readiness_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT_VALID="false"
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    # Check for keywords
    CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    if echo "$CONTENT" | grep -qi "googlebot\|mobile\|smartphone"; then
        if echo "$CONTENT" | grep -qi "viewport"; then
             REPORT_CONTENT_VALID="true"
        fi
    fi
fi

# 7. Check if App is Running
SF_RUNNING=$(is_screamingfrog_running && echo "true" || echo "false")

# 8. Create JSON Result
python3 << PYEOF
import json

result = {
    "task_start_epoch": $TASK_START_EPOCH,
    "sf_running": $SF_RUNNING,
    "user_agent_config": "$CURRENT_UA",
    "ua_is_mobile": $UA_IS_MOBILE,
    "internal_csv_path": "$INTERNAL_CSV",
    "internal_csv_valid": $INTERNAL_CSV_VALID,
    "internal_row_count": $INTERNAL_ROW_COUNT,
    "custom_csv_path": "$CUSTOM_CSV",
    "custom_csv_valid": $CUSTOM_CSV_VALID,
    "custom_has_viewport": $CUSTOM_HAS_VIEWPORT,
    "custom_row_count": $CUSTOM_ROW_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_CONTENT_VALID,
    "report_size": $REPORT_SIZE,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json