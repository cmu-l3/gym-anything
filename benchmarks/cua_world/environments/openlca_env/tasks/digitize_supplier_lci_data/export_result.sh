#!/bin/bash
# Post-task export script
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Close OpenLCA to safely query Derby
echo "Closing OpenLCA for verification..."
close_openlca
sleep 3

# 3. Find the Active Database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (assuming it's the one with USLCI imported)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_FOUND="false"
EXCHANGE_DATA="[]"

if [ -n "$ACTIVE_DB" ] && [ "$MAX_SIZE" -gt 5 ]; then
    echo "Querying database: $ACTIVE_DB"

    # Query to find the created process ID
    PROCESS_NAME="Supplier Injection Molding"
    PROC_QUERY="SELECT ID FROM TBL_PROCESSES WHERE NAME = '$PROCESS_NAME'"
    PROC_ID_RAW=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
    
    # Extract ID (Derby output contains headers, we need the number)
    PROC_ID=$(echo "$PROC_ID_RAW" | grep -oP '^\s*\K\d+' | head -1)

    if [ -n "$PROC_ID" ]; then
        PROCESS_FOUND="true"
        echo "Found Process ID: $PROC_ID"

        # Query exchanges: Amount, Flow Name, Is Input
        # Note: Derby doesn't support complex JSON output, so we dump a pipe-delimited list
        # We join TBL_EXCHANGES with TBL_FLOWS to get flow names
        EXCH_QUERY="SELECT e.RESULTING_AMOUNT_VALUE, f.NAME, e.IS_INPUT FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROC_ID"
        
        EXCH_RAW=$(derby_query "$ACTIVE_DB" "$EXCH_QUERY")
        
        # Clean up Derby output to simple CSV-like format for Python parsing
        # Remove empty lines, SQL prompts, headers
        EXCH_CLEAN=$(echo "$EXCH_RAW" | grep -v "^ij>" | grep -v "^--" | grep -v "rows selected" | grep -v "RESULTING" | sed '/^[[:space:]]*$/d')
        
        # Format as JSON string manually
        # Expected row format:  1.05   |Polypropylene resin  |1
        json_items=""
        while IFS='|' read -r amt flow is_input; do
            # Trim whitespace
            amt=$(echo "$amt" | xargs)
            flow=$(echo "$flow" | xargs)
            is_input=$(echo "$is_input" | xargs)
            
            if [ -n "$amt" ]; then
                [ -n "$json_items" ] && json_items="$json_items,"
                json_items="$json_items {\"amount\": \"$amt\", \"flow\": \"$flow\", \"is_input\": \"$is_input\"}"
            fi
        done <<< "$EXCH_CLEAN"
        
        EXCHANGE_DATA="[$json_items]"
    else
        echo "Process '$PROCESS_NAME' not found in database."
    fi
else
    echo "No valid database found."
fi

# 4. Export JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "process_found": $PROCESS_FOUND,
    "active_db_path": "$ACTIVE_DB",
    "exchanges": $EXCHANGE_DATA,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"