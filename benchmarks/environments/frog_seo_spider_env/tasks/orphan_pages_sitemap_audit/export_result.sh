#!/bin/bash
# Export script for Orphan Pages Sitemap Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Orphan Pages Sitemap Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/orphan_pages_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

INTERNAL_CSV=""
ORPHAN_CSV=""
INTERNAL_ROW_COUNT=0
ORPHAN_ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_CONTENT_LENGTH=0
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Analyze CSV files created after task start
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            
            # Identify "Orphan" or "Sitemap" CSV
            # Typical headers: "Address", "Source", "In Sitemap", "Orphan", "Status Code"
            # Or filename contains "orphan" or "sitemap"
            FILENAME=$(basename "$csv_file" | tr '[:upper:]' '[:lower:]')
            
            IS_ORPHAN="false"
            if echo "$FILENAME" | grep -q "orphan\|sitemap"; then
                IS_ORPHAN="true"
            elif echo "$HEADER" | grep -qi "In Sitemap\|Source\|Orphan"; then
                IS_ORPHAN="true"
            fi
            
            # Identify "Internal" CSV
            IS_INTERNAL="false"
            if echo "$HEADER" | grep -qi "Title 1\|Meta Description 1\|H1-1"; then
                IS_INTERNAL="true"
            elif echo "$FILENAME" | grep -q "internal"; then
                IS_INTERNAL="true"
            fi

            # Assign found files
            if [ "$IS_ORPHAN" = "true" ]; then
                ORPHAN_CSV="$csv_file"
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                ORPHAN_ROW_COUNT=$((TOTAL_LINES - 1))
            elif [ "$IS_INTERNAL" = "true" ]; then
                INTERNAL_CSV="$csv_file"
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                INTERNAL_ROW_COUNT=$((TOTAL_LINES - 1))
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# Check text report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT_LENGTH=$(wc -c < "$REPORT_PATH" || echo "0")
fi

# Count total new CSVs
NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

# Write result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "new_csv_count": $NEW_CSV_COUNT,
    "internal_csv_found": len("$INTERNAL_CSV") > 0,
    "internal_csv_path": "$INTERNAL_CSV",
    "internal_row_count": $INTERNAL_ROW_COUNT,
    "orphan_csv_found": len("$ORPHAN_CSV") > 0,
    "orphan_csv_path": "$ORPHAN_CSV",
    "orphan_row_count": $ORPHAN_ROW_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_length": $REPORT_CONTENT_LENGTH,
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/orphan_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/orphan_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="