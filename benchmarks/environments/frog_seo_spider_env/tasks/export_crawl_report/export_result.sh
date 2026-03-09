#!/bin/bash
# Export result script with error handling

# Trap errors to ensure result file is always created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Export Crawl Report Result ==="

# Take final screenshot
take_screenshot /tmp/screamingfrog_export_final.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"

# Get initial state
INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")

# Find new CSV files
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l)
NEW_FILES_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))

# Find the newest CSV file
NEWEST_CSV=""
NEWEST_CSV_ROWS=0
FILE_CREATED="false"
FILE_CONTENT_VALID="false"

if [ "$NEW_FILES_COUNT" -gt 0 ]; then
    FILE_CREATED="true"
    # Get the most recently modified CSV
    NEWEST_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)

    if [ -f "$NEWEST_CSV" ]; then
        # Count rows (minus header)
        TOTAL_ROWS=$(wc -l < "$NEWEST_CSV")
        NEWEST_CSV_ROWS=$((TOTAL_ROWS - 1))

        # Check if file has meaningful content
        if [ "$NEWEST_CSV_ROWS" -ge 1 ]; then
            FILE_CONTENT_VALID="true"
        fi

        # Copy the export file for verification
        cp "$NEWEST_CSV" /tmp/exported_crawl_report.csv 2>/dev/null || true
    fi
fi

# Also check for files modified after task started
MODIFIED_FILES=0
TASK_START_TIME_ISO=$(cat /tmp/task_start_time 2>/dev/null || echo "1970-01-01T00:00:00")
TASK_START_EPOCH=$(date -d "$TASK_START_TIME_ISO" +%s 2>/dev/null || echo "0")

# Count files modified after task started
for f in "$EXPORT_DIR"/*.csv; do
    if [ -f "$f" ]; then
        FILE_MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
            MODIFIED_FILES=$((MODIFIED_FILES + 1))
            echo "Found file modified after task start: $f"
        fi
    fi
done

# Check if Screaming Frog is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
else
    SF_RUNNING="false"
fi

# Get window info for additional context
WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "screaming frog\|seo spider" | head -1 | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_created": $FILE_CREATED,
    "file_content_valid": $FILE_CONTENT_VALID,
    "new_files_count": $NEW_FILES_COUNT,
    "modified_files_count": $MODIFIED_FILES,
    "newest_csv_path": "$NEWEST_CSV",
    "newest_csv_rows": $NEWEST_CSV_ROWS,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "screaming_frog_running": $SF_RUNNING,
    "window_info": "$WINDOW_INFO",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="
