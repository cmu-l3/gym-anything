#!/bin/bash
set -e
echo "=== Exporting Stoichiometry Task Results ==="

source /workspace/utils/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify Database
DB_PATH=$(ensure_uslci_database)
DB_FOUND="false"
if [ -n "$DB_PATH" ]; then
    DB_FOUND="true"
fi

# 3. Query Database for Process and Exchanges
# We need to find the process created by the agent.
# Name should contain "Stoichiometric" or "Methane Combustion"
PROCESS_ID=""
PROCESS_NAME=""
EXCHANGES_JSON="[]"

if [ "$DB_FOUND" = "true" ]; then
    # Close OpenLCA to unlock Derby DB for querying
    close_openlca
    sleep 3

    echo "Querying database at $DB_PATH..."
    
    # Find Process ID
    # Search for "Stoichiometric Methane" or just "Methane Combustion"
    QUERY_PROC="SELECT ID, NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%stoichiometric%' OR (LOWER(NAME) LIKE '%methane%' AND LOWER(NAME) LIKE '%combustion%') FETCH FIRST 1 ROWS ONLY;"
    PROC_RESULT=$(derby_query "$DB_PATH" "$QUERY_PROC")
    
    # Parse ID (simple grep, assuming ID is the first number)
    PROCESS_ID=$(echo "$PROC_RESULT" | grep -oP '^\s*\K\d+' | head -1)
    
    if [ -n "$PROCESS_ID" ]; then
        PROCESS_NAME="Found ID $PROCESS_ID"
        
        # Get Exchanges: Flow Name, Is Input, Amount, Unit
        # Join TBL_EXCHANGES with TBL_FLOWS
        # Note: Derby doesn't support easy JSON export, so we format as CSV-like and parse in Python/Bash
        QUERY_EXCH="SELECT f.NAME, e.IS_INPUT, e.RESULT_AMOUNT FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROCESS_ID;"
        EXCH_RAW=$(derby_query "$DB_PATH" "$QUERY_EXCH")
        
        # Parse raw Derby output into JSON array
        # Derby output lines look like: "FlowName  |1|4.0" (formatting varies)
        # We'll use a python one-liner to robustly parse the output lines
        EXCHANGES_JSON=$(python3 -c "
import sys, json, re
lines = sys.stdin.readlines()
exchanges = []
for line in lines:
    line = line.strip()
    # Skip headers and separators
    if not line or line.startswith('NAME') or line.startswith('--'): continue
    # Split by whitespace, but Flow Name might have spaces. 
    # Usually Derby output columns are separated by spaces. The last two columns are IS_INPUT (0/1) and AMOUNT (float).
    # We can split from the right.
    parts = line.split()
    if len(parts) >= 3:
        try:
            amount = float(parts[-1])
            is_input_raw = parts[-2]
            # IS_INPUT might be 1/0 or true/false depending on version
            is_input = (is_input_raw == '1' or is_input_raw.lower() == 'true')
            name = ' '.join(parts[:-2])
            exchanges.append({'name': name, 'is_input': is_input, 'amount': amount})
        except ValueError:
            continue
print(json.dumps(exchanges))
" <<< "$EXCH_RAW")
    fi
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "db_found": $DB_FOUND,
    "process_found": $([ -n "$PROCESS_ID" ] && echo "true" || echo "false"),
    "process_id": "$PROCESS_ID",
    "exchanges": $EXCHANGES_JSON,
    "task_end_timestamp": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json