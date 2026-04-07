#!/bin/bash
# Export script for Office Chair LCA Recreation task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
RESULTS_DIR="/home/ga/LCA_Results"
CSV_FILE="$RESULTS_DIR/chair_impact.csv"
VERDICT_FILE="$RESULTS_DIR/verification_verdict.txt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Output Files
CSV_EXISTS="false"
CSV_SIZE=0
VERDICT_EXISTS="false"
VERDICT_CONTENT=""

if [ -f "$CSV_FILE" ]; then
    FMTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c %s "$CSV_FILE" 2>/dev/null || echo "0")
    fi
fi

if [ -f "$VERDICT_FILE" ]; then
    FMTIME=$(stat -c %Y "$VERDICT_FILE" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        VERDICT_EXISTS="true"
        VERDICT_CONTENT=$(cat "$VERDICT_FILE" | head -n 5)
    fi
fi

# 2. Database Verification (Derby Query)
# We need to find the active database and check for the "Office Chair Assembly" process
close_openlca
sleep 5

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (assumption: imported USLCI is larger than empty)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    SZ=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${SZ:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${SZ:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_FOUND="false"
PROCESS_NAME=""
INPUT_COUNT=0

if [ -n "$ACTIVE_DB" ] && [ "$MAX_SIZE" -gt 5 ]; then
    echo "Checking database: $ACTIVE_DB"
    
    # Query to find the process ID for "Office Chair Assembly"
    # Note: Derby SQL syntax. 
    # TBL_PROCESSES: ID, NAME, ...
    # TBL_EXCHANGES: F_OWNER (process id), F_FLOW (flow id), AMOUNT, IS_INPUT
    
    # 1. Find Process ID
    FIND_PROC_SQL="SELECT ID, NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%office%chair%assembly%';"
    PROC_RESULT=$(derby_query "$ACTIVE_DB" "$FIND_PROC_SQL")
    
    # Extract ID (Assuming output format like 'ID | NAME ...')
    PROC_ID=$(echo "$PROC_RESULT" | grep -oP '^\s*\K\d+(?=\s*\|)' | head -1)
    
    if [ -n "$PROC_ID" ]; then
        PROCESS_FOUND="true"
        PROCESS_NAME=$(echo "$PROC_RESULT" | grep "$PROC_ID" | cut -d'|' -f2 | xargs)
        
        # 2. Count Input Exchanges for this Process
        # IS_INPUT = 1 (true)
        COUNT_SQL="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_OWNER = $PROC_ID AND IS_INPUT = 1;"
        COUNT_RESULT=$(derby_query "$ACTIVE_DB" "$COUNT_SQL")
        INPUT_COUNT=$(echo "$COUNT_RESULT" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "verdict_exists": $VERDICT_EXISTS,
    "verdict_content": "$(echo "$VERDICT_CONTENT" | sed 's/"/\\"/g')",
    "process_found": $PROCESS_FOUND,
    "process_name": "$PROCESS_NAME",
    "input_count": ${INPUT_COUNT:-0},
    "db_size_mb": $MAX_SIZE,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json