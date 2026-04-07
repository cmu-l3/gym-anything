#!/bin/bash
# Export script for Soybean Crushing Allocation task
# Queries the Derby database to verify the process and allocation factors exist

source /workspace/scripts/task_utils.sh

echo "=== Exporting Soybean Crushing Allocation Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Close OpenLCA to unlock the Derby database
# This is critical because Derby (embedded) allows only one connection
echo "Closing OpenLCA to query database..."
close_openlca
sleep 5

# 3. Find the active database
# We look for the most recently modified database directory
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
LATEST_TIME=0

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    MOD_TIME=$(stat -c %Y "$db_path" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$LATEST_TIME" ]; then
        LATEST_TIME="$MOD_TIME"
        ACTIVE_DB="$db_path"
    fi
done

echo "Active database: $ACTIVE_DB"

# 4. Query the database
# We need to find:
# - The Process ID for "Soybean Crushing (Custom)"
# - The Allocation Factors for that Process ID
# - The Output Flows for that Process ID

DERBY_OUTPUT=""
PROCESS_FOUND="false"
FACTORS_FOUND="false"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying Derby database..."
    
    # Query 1: Find Process ID and Name
    # We select ID, NAME, and F_QUANTITATIVE_REFERENCE (flow ID)
    PROC_QUERY="SELECT ID, NAME FROM TBL_PROCESSES WHERE NAME LIKE '%Soybean Crushing (Custom)%';"
    PROC_RESULT=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
    echo "Process Query Result: $PROC_RESULT"
    
    # Extract Process ID (simple regex approximation in bash)
    # Assumes output format like: "ID | NAME ... \n 12345 | Soybean..."
    PROC_ID=$(echo "$PROC_RESULT" | grep -oP '^\s*\K\d+(?=\s*\|\s*Soybean)' | head -1)
    
    if [ -n "$PROC_ID" ]; then
        PROCESS_FOUND="true"
        echo "Found Process ID: $PROC_ID"
        
        # Query 2: Get Allocation Factors for this process
        # TBL_ALLOCATION_FACTORS columns: ID, VALUE, F_PROCESS, F_PRODUCT (flow id), ALLOCATION_TYPE
        # Allocation types: 0=Physical, 1=Economic, 2=Causal (checking schema is hard, we look for values)
        FACTOR_QUERY="SELECT VALUE, F_PRODUCT FROM TBL_ALLOCATION_FACTORS WHERE F_PROCESS = $PROC_ID;"
        FACTOR_RESULT=$(derby_query "$ACTIVE_DB" "$FACTOR_QUERY")
        echo "Factor Query Result: $FACTOR_RESULT"
        
        # Query 3: Get Exchanges (to map Flow IDs to Names and amounts)
        # TBL_EXCHANGES: ID, F_FLOW, RESULTing_AMOUNT_VALUE, IS_INPUT
        EXCHANGE_QUERY="SELECT TBL_EXCHANGES.RESULTING_AMOUNT_VALUE, TBL_FLOWS.NAME FROM TBL_EXCHANGES JOIN TBL_FLOWS ON TBL_EXCHANGES.F_FLOW = TBL_FLOWS.ID WHERE TBL_EXCHANGES.F_OWNER = $PROC_ID;"
        EXCHANGE_RESULT=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
        echo "Exchange Query Result: $EXCHANGE_RESULT"
        
        # Combine results for JSON
        DERBY_OUTPUT="PROCESS_ID: $PROC_ID\n\nFACTORS:\n$FACTOR_RESULT\n\nEXCHANGES:\n$EXCHANGE_RESULT"
    else
        echo "Process 'Soybean Crushing (Custom)' not found in database."
        DERBY_OUTPUT="Process not found"
    fi
else
    echo "No active database found."
    DERBY_OUTPUT="No database found"
fi

# 5. Create JSON result
# We embed the raw query output strings to be parsed by python verifier
# Using python to escape the string safely
python3 << EOF
import json
import os

output = {
    "process_found": "$PROCESS_FOUND",
    "active_db": "$ACTIVE_DB",
    "raw_derby_output": """$DERBY_OUTPUT""",
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json