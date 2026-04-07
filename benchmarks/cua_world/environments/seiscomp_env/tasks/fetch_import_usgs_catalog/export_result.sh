#!/bin/bash
echo "=== Exporting fetch_import_usgs_catalog results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query final event count from DB
CURRENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")

# Target file paths
XML_PATH="/home/ga/aftershocks_usgs.xml"
SCML_PATH="/home/ga/aftershocks.scml"
CSV_PATH="/home/ga/imported_events.csv"

# Check file stats
get_file_info() {
    local file=$1
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
        local created="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created="true"
        fi
        echo "{\"exists\": true, \"created_during_task\": $created, \"size\": $size}"
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0}"
    fi
}

XML_INFO=$(get_file_info "$XML_PATH")
SCML_INFO=$(get_file_info "$SCML_PATH")
CSV_INFO=$(get_file_info "$CSV_PATH")

CSV_ROWS=0
if [ -f "$CSV_PATH" ]; then
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_event_count": $INITIAL_COUNT,
    "current_event_count": $CURRENT_COUNT,
    "xml_file": $XML_INFO,
    "scml_file": $SCML_INFO,
    "csv_file": $CSV_INFO,
    "csv_rows": $CSV_ROWS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="