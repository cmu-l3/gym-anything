#!/bin/bash
# Export script for Transport Modal Split Optimization

source /workspace/scripts/task_utils.sh

# Fallback check
if ! type derby_query &>/dev/null; then
    echo "Error: derby_query function missing"
    exit 1
fi

echo "=== Exporting Transport Optimization Results ==="

# 1. Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check for Report File
REPORT_FILE="/home/ga/LCA_Results/optimization_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_TIMESTAMP=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 5)
    REPORT_TIMESTAMP=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_TIMESTAMP" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Query Derby Database for Process, Parameters, and Formulas
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (likely the one with USLCI imported)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_FOUND="false"
PARAM_FOUND="false"
FORMULA_FOUND="false"
PARAM_VALUE=""
PROCESS_NAME="freight_route_optimized"

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo " querying database: $ACTIVE_DB"
    
    # Close OpenLCA to unlock DB for Derby
    close_openlca
    sleep 3
    
    # A. Check if Process exists
    # Query: SELECT ID FROM TBL_PROCESSES WHERE NAME LIKE '%freight_route_optimized%'
    PROC_QUERY="SELECT ID FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%freight_route_optimized%'"
    PROC_ID_RESULT=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
    
    # Extract ID (Derby output formatting handling)
    PROC_ID=$(echo "$PROC_ID_RESULT" | grep -oP '^\s*\K\d+' | head -1)
    
    if [ -n "$PROC_ID" ]; then
        PROCESS_FOUND="true"
        echo "  Process found with ID: $PROC_ID"
        
        # B. Check for Parameter 'rail_share' associated with this process (or global)
        # Note: Parameters can be in TBL_PARAMETERS. We check for name 'rail_share'
        PARAM_QUERY="SELECT VALUE FROM TBL_PARAMETERS WHERE LOWER(NAME)='rail_share'"
        PARAM_RESULT=$(derby_query "$ACTIVE_DB" "$PARAM_QUERY")
        PARAM_VALUE=$(echo "$PARAM_RESULT" | grep -oP '^\s*\K[0-9\.]+' | head -1)
        
        if [ -n "$PARAM_VALUE" ]; then
            PARAM_FOUND="true"
            echo "  Parameter rail_share found: $PARAM_VALUE"
        fi
        
        # C. Check Exchanges for Formulas
        # We need exchanges linked to this process that utilize the parameter
        # Look for 'rail_share' in AMOUNT_FORMULA column of TBL_EXCHANGES for this process
        FORMULA_QUERY="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_OWNER='$PROC_ID' AND LOWER(AMOUNT_FORMULA) LIKE '%rail_share%'"
        FORMULA_COUNT_RES=$(derby_query "$ACTIVE_DB" "$FORMULA_QUERY")
        FORMULA_COUNT=$(echo "$FORMULA_COUNT_RES" | grep -oP '^\s*\K\d+' | head -1)
        
        if [ "$FORMULA_COUNT" -gt 0 ] 2>/dev/null; then
            FORMULA_FOUND="true"
            echo "  Exchanges with formulas found: $FORMULA_COUNT"
        fi
    else
        echo "  Process 'freight_route_optimized' not found in DB."
    fi
else
    echo "  No active database found."
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content": "$(echo "$REPORT_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
    "process_found": $PROCESS_FOUND,
    "parameter_found": $PARAM_FOUND,
    "parameter_value_db": "$PARAM_VALUE",
    "formulas_found": $FORMULA_FOUND,
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 5. Save safe copy
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json