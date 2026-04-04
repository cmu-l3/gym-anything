#!/bin/bash
# Export script for Hreflang Validation Audit task

# Ensure error trapping to always produce result file
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Hreflang Validation Audit Result ==="

# Capture final state for VLM verification
take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/hreflang_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
HREFLANG_CSV_PATH=""
INTERNAL_CSV_PATH=""
HREFLANG_CSV_FOUND="false"
INTERNAL_CSV_FOUND="false"
INTERNAL_HAS_TARGET_DOMAIN="false"
INTERNAL_ROW_COUNT=0
REPORT_FOUND="false"
REPORT_SIZE=0
REPORT_CONTENT=""

# Check if SF is still running
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 1. Analyze CSV exports
# We look for files modified AFTER task start
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Only check new/modified files
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            FILENAME=$(basename "$csv_file" | tr '[:upper:]' '[:lower:]')
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            
            # Check for Hreflang CSV
            # Criteria: Filename contains 'hreflang' OR Header contains hreflang specific columns
            if [[ "$FILENAME" == *"hreflang"* ]] || echo "$HEADER" | grep -qi "Hreflang\|Region\|Language Code"; then
                HREFLANG_CSV_FOUND="true"
                HREFLANG_CSV_PATH="$csv_file"
                echo "Found Hreflang CSV: $csv_file"
            fi
            
            # Check for Internal CSV
            # Criteria: Filename contains 'internal' OR Header contains standard internal columns
            if [[ "$FILENAME" == *"internal"* ]] || echo "$HEADER" | grep -qi "Meta Description\|H1-1\|Word Count"; then
                # Differentiate from Hreflang if it accidentally matched both (unlikely but safe)
                if [[ "$FILENAME" != *"hreflang"* ]]; then
                    INTERNAL_CSV_FOUND="true"
                    INTERNAL_CSV_PATH="$csv_file"
                    echo "Found Internal CSV: $csv_file"
                    
                    # Verification: Check content for target domain and row count
                    if grep -qi "crawler-test.com" "$csv_file"; then
                        INTERNAL_HAS_TARGET_DOMAIN="true"
                    fi
                    # Count rows (excluding header)
                    ROW_COUNT=$(wc -l < "$csv_file")
                    INTERNAL_ROW_COUNT=$((ROW_COUNT - 1))
                fi
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Analyze Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_FOUND="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read first 1000 chars for verification (avoid huge reads)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
    echo "Found Report: $REPORT_PATH ($REPORT_SIZE bytes)"
fi

# 3. Get Window Title for extra context
WINDOW_TITLE=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 | sed 's/"/\\"/g' || echo "")

# 4. Generate JSON Result
# Using Python for robust JSON generation
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "hreflang_csv_found": "$HREFLANG_CSV_FOUND" == "true",
    "hreflang_csv_path": "$HREFLANG_CSV_PATH",
    "internal_csv_found": "$INTERNAL_CSV_FOUND" == "true",
    "internal_csv_path": "$INTERNAL_CSV_PATH",
    "internal_has_target_domain": "$INTERNAL_HAS_TARGET_DOMAIN" == "true",
    "internal_row_count": $INTERNAL_ROW_COUNT,
    "report_found": "$REPORT_FOUND" == "true",
    "report_size": $REPORT_SIZE,
    "report_content_snippet": """$REPORT_CONTENT""",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON generated successfully")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json