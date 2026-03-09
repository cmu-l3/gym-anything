#!/bin/bash
# Export script for Thin Content Word Count Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Thin Content Audit Result ==="

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/thin_content_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# --- Analyze CSV Exports ---
NEWEST_CSV=""
HAS_WORD_COUNT="false"
HAS_TARGET_DOMAIN="false"
ROW_COUNT=0
CSV_CREATED_DURING_TASK="false"

# Find the most relevant CSV file created after task start
if [ -d "$EXPORT_DIR" ]; then
    # Sort by modification time, newest first
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Only check files created/modified after task start
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            CSV_CREATED_DURING_TASK="true"
            
            # Check for "Word Count" column (case insensitive)
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            if echo "$HEADER" | grep -qi "Word Count"; then
                HAS_WORD_COUNT="true"
                NEWEST_CSV="$csv_file"
                
                # Check for target domain in content
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    HAS_TARGET_DOMAIN="true"
                fi
                
                # Count rows (minus header)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "0")
                ROW_COUNT=$((TOTAL_LINES - 1))
                
                # Found a good candidate, verify it's the right one
                break
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -printf '%T@ %p\0' | sort -znr | cut -z -d ' ' -f 2-)
fi

# If we found a valid CSV, copy it to tmp for the verifier
if [ -n "$NEWEST_CSV" ]; then
    cp "$NEWEST_CSV" /tmp/audit_export.csv 2>/dev/null || true
fi

# --- Analyze Report File ---
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy report to tmp for verifier
    cp "$REPORT_PATH" /tmp/audit_report.txt 2>/dev/null || true
fi

# --- Check App State ---
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- Create Result JSON ---
python3 << PYEOF
import json, os

result = {
    "sf_running": $SF_RUNNING == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_found": len("$NEWEST_CSV") > 0,
    "csv_has_word_count": "$HAS_WORD_COUNT" == "true",
    "csv_has_target_domain": "$HAS_TARGET_DOMAIN" == "true",
    "csv_row_count": $ROW_COUNT,
    "csv_created_during_task": "$CSV_CREATED_DURING_TASK" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size": $REPORT_SIZE,
    "report_created_during_task": "$REPORT_CREATED_DURING_TASK" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="