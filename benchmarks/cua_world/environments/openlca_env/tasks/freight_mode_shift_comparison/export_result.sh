#!/bin/bash
# Export script for Freight Mode Shift Comparison task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Freight Mode Shift Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/LCA_Results/mode_shift_report.txt"

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (first 500 chars)
    REPORT_CONTENT=$(head -c 500 "$OUTPUT_FILE")
fi

# 2. Query Derby Database for Process State
# We need to check if "Distribution Scenario" exists and if it has a Train input
DB_DIR="/home/ga/openLCA-data-1.4/databases"
PROCESS_FOUND="false"
TRAIN_INPUT_FOUND="false"
TRUCK_INPUT_FOUND="false" # Should be gone or replaced, but checking helps context

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
    echo "Checking database: $ACTIVE_DB"
    
    # Close OpenLCA to unlock Derby
    close_openlca
    sleep 3
    
    # Query: Find ID of process named 'Distribution Scenario'
    PROCESS_QUERY="SELECT ID FROM TBL_PROCESSES WHERE NAME LIKE '%Distribution Scenario%'"
    PROCESS_ID_RESULT=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY")
    
    # Parse ID (Derby output is messy)
    # Look for a number in the output
    PROCESS_ID=$(echo "$PROCESS_ID_RESULT" | grep -oP '^\s*\K\d+' | head -1)
    
    if [ -n "$PROCESS_ID" ]; then
        PROCESS_FOUND="true"
        echo "Found process ID: $PROCESS_ID"
        
        # Query: Check exchanges for this process
        # We look for exchanges linking to flows with 'train' or 'rail' in name
        # TBL_EXCHANGES.F_OWNER = PROCESS_ID
        # TBL_EXCHANGES.F_FLOW -> TBL_FLOWS.ID
        
        EXCHANGE_QUERY="SELECT f.NAME FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROCESS_ID"
        EXCHANGES_RESULT=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
        
        if echo "$EXCHANGES_RESULT" | grep -qi "train\|rail"; then
            TRAIN_INPUT_FOUND="true"
        fi
        if echo "$EXCHANGES_RESULT" | grep -qi "truck\|road"; then
            TRUCK_INPUT_FOUND="true"
        fi
    fi
else
    echo "No valid database found."
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "process_found": $PROCESS_FOUND,
    "train_input_found": $TRAIN_INPUT_FOUND,
    "truck_input_found": $TRUCK_INPUT_FOUND,
    "report_content_b64": "$(echo "$REPORT_CONTENT" | base64 -w 0)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"