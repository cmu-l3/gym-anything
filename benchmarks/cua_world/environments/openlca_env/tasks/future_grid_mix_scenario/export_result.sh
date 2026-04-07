#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Grid Mix Results ==="

# 1. Basic File Checks
RESULT_CSV="/home/ga/LCA_Results/grid_2035_results.csv"
DOC_TXT="/home/ga/LCA_Results/mix_composition.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

RESULT_EXISTS="false"
RESULT_CREATED_DURING_TASK="false"
DOC_EXISTS="false"

if [ -f "$RESULT_CSV" ]; then
    RESULT_EXISTS="true"
    FMTIME=$(stat -c %Y "$RESULT_CSV")
    if [ "$FMTIME" -gt "$TASK_START" ]; then
        RESULT_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$DOC_TXT" ]; then
    DOC_EXISTS="true"
fi

# 2. Database Inspection (The Core Verification)
# We need to query the Derby database to see if the "Mix" process exists 
# and what its inputs are.

# Find the active database path
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

PROCESS_FOUND="false"
INPUTS_JSON="[]"

if [ -n "$ACTIVE_DB" ]; then
    echo "Inspecting Database: $ACTIVE_DB"
    
    # Query to find the process ID for "US Electricity Grid Mix 2035"
    # We use LIKE to be lenient on exact naming
    PID_QUERY="SELECT ID FROM TBL_PROCESSES WHERE NAME LIKE '%Grid Mix 2035%' FETCH FIRST 1 ROWS ONLY;"
    PID_RESULT=$(derby_query "$ACTIVE_DB" "$PID_QUERY")
    # Extract ID (Derby output contains headers, we filter for digits)
    PID=$(echo "$PID_RESULT" | grep -oE '^[0-9]+' | head -1)

    if [ -n "$PID" ]; then
        PROCESS_FOUND="true"
        echo "Found Process ID: $PID"

        # Query Exchanges (Inputs) for this process
        # We need: Amount, Unit, and the Name of the flow/provider
        # Note: Joining tables in raw Derby IJ via bash is messy. 
        # We will fetch the exchange table for this owner and dump it.
        # TBL_EXCHANGES columns: ID, F_OWNER, AMOUNT, F_FLOW, F_DEFAULT_PROVIDER
        
        # We join with TBL_FLOWS to get names to identify Wind vs Solar vs Coal etc.
        # Note: This query is complex for simple shell execution, so we keep it simple 
        # and parse the output in Python if possible, or just dump raw rows.
        
        SQL="SELECT e.AMOUNT, f.NAME FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PID AND e.IS_INPUT = 1;"
        INPUTS_RAW=$(derby_query "$ACTIVE_DB" "$SQL")
        
        # Convert raw Derby output to a JSON-like string for the python verifier
        # Derby output format:
        # AMOUNT          |NAME
        # -----------------------------------
        # 0.4             |Electricity, wind
        
        # We'll just save the raw string; verifier.py will parse regex
        INPUTS_DUMP="$INPUTS_RAW"
    fi
fi

# 3. Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "result_csv_exists": $RESULT_EXISTS,
    "result_fresh": $RESULT_CREATED_DURING_TASK,
    "doc_exists": $DOC_EXISTS,
    "process_found": $PROCESS_FOUND,
    "inputs_dump": $(jq -n --arg v "$INPUTS_DUMP" '$v'),
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

export_json_result "/tmp/task_result.json" < "$TEMP_JSON"
rm "$TEMP_JSON"