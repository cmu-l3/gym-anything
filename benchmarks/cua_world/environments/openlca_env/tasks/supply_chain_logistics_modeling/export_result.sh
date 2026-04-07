#!/bin/bash
# Export script for Supply Chain Logistics Modeling task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Output CSV
CSV_PATH="/home/ga/LCA_Results/workbench_results.csv"
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH")
fi

# 3. Query Derby Database for Process Inputs (The core verification)
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find the most recently modified database directory
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

PROCESS_FOUND="false"
INPUTS_JSON="[]"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database at $ACTIVE_DB..."
    
    # Query to get the ID of the 'Global Workbench Assembly' process
    # Note: Derby uses upper case for table names usually
    PROCESS_QUERY="SELECT ID FROM TBL_PROCESSES WHERE NAME LIKE '%Global Workbench%'"
    PROCESS_ID=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY" | grep -oE '[0-9]+' | head -1)
    
    if [ -n "$PROCESS_ID" ]; then
        PROCESS_FOUND="true"
        echo "Found Process ID: $PROCESS_ID"
        
        # Query to get flows and amounts for this process
        # Joining TBL_EXCHANGES (e) with TBL_FLOWS (f)
        # TBL_EXCHANGES columns: F_OWNER (process id), F_FLOW (flow id), AMOUNT_VALUE
        EXCHANGE_QUERY="SELECT f.NAME, e.AMOUNT_VALUE FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROCESS_ID"
        
        # Execute query and capture raw output
        RAW_EXCHANGES=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
        
        # Parse the raw Derby output into a JSON array
        # Derby output often looks like:
        # NAME | AMOUNT_VALUE
        # -------------------
        # Wood | 50.0
        # ...
        
        # We use python to robustly parse this text output into JSON
        INPUTS_JSON=$(python3 -c "
import sys, json, re
raw = sys.stdin.read()
inputs = []
# Skip header lines and look for data rows
for line in raw.split('\n'):
    line = line.strip()
    # Simple heuristic: line must contain a pipe or lots of spaces separation
    # Derby ij output usually separates columns with spaces/tabs
    # We look for lines that end with a number
    match = re.search(r'^\s*(.*?)\s+(\d+\.?\d*(?:E[+-]?\d+)?)\s*$', line)
    if match:
        name = match.group(1).strip()
        try:
            amount = float(match.group(2))
            inputs.append({'name': name, 'amount': amount})
        except ValueError:
            continue
print(json.dumps(inputs))
" <<< "$RAW_EXCHANGES")
    else
        echo "Process 'Global Workbench Assembly' not found in database."
    fi
else
    echo "No active database found."
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "process_found": $PROCESS_FOUND,
    "inputs": $INPUTS_JSON,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json