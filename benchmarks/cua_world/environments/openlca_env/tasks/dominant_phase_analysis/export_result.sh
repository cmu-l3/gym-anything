#!/bin/bash
# Export script for Dominant Phase Analysis task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Dominant Phase Analysis Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get task timing
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Check Report File
REPORT_FILE="/home/ga/LCA_Results/dominance_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 500) # Read first 500 chars
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Query Database (Derby) to verify model structure
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find the most recently modified database directory
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

PROCESSES_FOUND="[]"
HAS_STEEL_INPUT="false"
HAS_ELEC_INPUT="false"

if [ -n "$ACTIVE_DB" ]; then
    echo "Checking database: $ACTIVE_DB"
    
    # Check for specific process names
    # Note: Derby queries are case-sensitive usually, but we'll try standard SQL
    # We select names that match our expectations
    P_QUERY="SELECT NAME FROM TBL_PROCESSES WHERE NAME LIKE '%Pump%'"
    PROCESS_NAMES=$(derby_query "$ACTIVE_DB" "$P_QUERY")
    
    # Parse output to JSON array of strings
    # Clean up Derby output artifacts (ij headers)
    CLEAN_NAMES=$(echo "$PROCESS_NAMES" | grep "Pump" | sed 's/^[ \t]*//;s/[ \t]*$//' | tr '\n' ',' | sed 's/,$//')
    PROCESSES_FOUND="[\"${CLEAN_NAMES//,/\",\"}\"]"

    # Check for exchange values (heuristic)
    # 50.0 for steel, 20000.0 for electricity
    # We query the exchanges table for these specific values to see if they were entered
    VAL_QUERY="SELECT RESULT_AMOUNT FROM TBL_EXCHANGES WHERE RESULT_AMOUNT = 50.0 OR RESULT_AMOUNT = 20000.0"
    VALUES_FOUND=$(derby_query "$ACTIVE_DB" "$VAL_QUERY")
    
    if echo "$VALUES_FOUND" | grep -q "50\.0"; then
        HAS_STEEL_INPUT="true"
    fi
    if echo "$VALUES_FOUND" | grep -q "20000\.0"; then
        HAS_ELEC_INPUT="true"
    fi
fi

# 5. Check if OpenLCA is still running
APP_RUNNING=$(pgrep -f "openLCA\|openlca" > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "processes_found": $PROCESSES_FOUND,
    "has_steel_input_50": $HAS_STEEL_INPUT,
    "has_elec_input_20000": $HAS_ELEC_INPUT,
    "app_running": $APP_RUNNING,
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"