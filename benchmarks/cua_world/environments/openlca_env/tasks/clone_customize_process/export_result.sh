#!/bin/bash
# Export script for Clone & Customize Process task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Clone & Customize Process Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check Report File
REPORT_FILE="/home/ga/LCA_Results/process_customization_report.csv"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT=""
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FMTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Capture content for python verifier to parse numbers
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 2000)
fi

# 3. Check OpenLCA State & DB content
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PROCESS_COUNT=0
NEW_PROCESS_FOUND="false"
NEW_PROCESS_NAME=""
DB_FOUND="false"

# Find active database
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    
    # Count total processes
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
    
    # Search for the custom process name in TBL_PROCESSES
    # We look for names containing "Facility" or "Site" or "XYZ"
    # Note: derby_query returns text output, we grep it
    QUERY="SELECT NAME FROM TBL_PROCESSES WHERE UPPER(NAME) LIKE '%FACILITY%' OR UPPER(NAME) LIKE '%SITE%' OR UPPER(NAME) LIKE '%XYZ%';"
    QUERY_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY" 2>/dev/null)
    
    if echo "$QUERY_RESULT" | grep -qi "Facility\|Site\|XYZ"; then
        NEW_PROCESS_FOUND="true"
        # Extract the name (rough extraction from ij output)
        NEW_PROCESS_NAME=$(echo "$QUERY_RESULT" | grep -i "Facility\|Site\|XYZ" | head -1 | xargs)
    fi
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# We use Python to escape the report content safely for JSON
python3 -c "
import json
import os

data = {
    'report_exists': $REPORT_EXISTS,
    'report_size': $REPORT_SIZE,
    'file_created_during_task': '${FILE_CREATED_DURING_TASK:-false}',
    'report_content': '''$REPORT_CONTENT''',
    'db_found': ${DB_FOUND:-false},
    'process_count': ${PROCESS_COUNT:-0},
    'new_process_found': ${NEW_PROCESS_FOUND:-false},
    'new_process_name': '$NEW_PROCESS_NAME'
}
print(json.dumps(data))
" > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="