#!/bin/bash
# Export script for Grid Mix Source Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Grid Mix Analysis Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Basic Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/LCA_Results/grid_source_breakdown.csv"

# 3. Check Output File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check for Analysis Evidence in Logs/Window Titles
# We look for terms related to the analysis view or grouping
ANALYSIS_WINDOW_OPEN="false"
GROUPING_EVIDENCE="false"

WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
if echo "$WINDOWS_LIST" | grep -qi "Analysis\|Contribution\|Group"; then
    ANALYSIS_WINDOW_OPEN="true"
fi

if [ -f "/tmp/openlca_ga.log" ]; then
    if grep -qi "Grouping\|Group" /tmp/openlca_ga.log; then
        GROUPING_EVIDENCE="true"
    fi
fi

# 5. Check Database State (Prerequisite)
# Close OpenLCA to release Derby lock
close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PS_COUNT=0
DB_FOUND="false"

# Find active DB (largest/most recent)
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    CURRENT_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${CURRENT_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${CURRENT_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    # Query product systems
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis_window_open": $ANALYSIS_WINDOW_OPEN,
    "grouping_evidence": $GROUPING_EVIDENCE,
    "db_found": $DB_FOUND,
    "ps_count": ${PS_COUNT:-0},
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="