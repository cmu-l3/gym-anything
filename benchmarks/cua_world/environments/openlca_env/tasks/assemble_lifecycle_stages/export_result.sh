#!/bin/bash
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check Result File
OUTPUT_FILE="/home/ga/LCA_Results/pvc_lifecycle_results.csv"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Database Inspection (Derby)
# We need to query the internal database to check the process structure.
# First, find the active database directory.
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest/most recent DB (likely the one the agent created/imported)
for db in "$DB_DIR"/*/; do
    if [ -d "$db" ]; then
        SIZE=$(du -s "$db" | cut -f1)
        if [ "$SIZE" -gt "$MAX_SIZE" ]; then
            MAX_SIZE=$SIZE
            ACTIVE_DB="$db"
        fi
    fi
done

PROCESS_FOUND="false"
PROCESS_ID=""
EXCHANGES_JSON="[]"

if [ -n "$ACTIVE_DB" ]; then
    echo "Inspecting database: $ACTIVE_DB"
    
    # Close OpenLCA to release DB lock for querying
    close_openlca
    sleep 2

    # Query 1: Find the Process ID
    # Look for a process with "PVC" and "Assembly" or "Life Cycle" in name
    QUERY_NAME="SELECT ID, NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%pvc%';"
    RESULT_NAME=$(derby_query "$ACTIVE_DB" "$QUERY_NAME")
    
    # Parse ID from result (simplified parsing)
    # Example output: "ID | NAME \n 123 | PVC Pipe Life Cycle Assembly"
    # We grep for the line matching our target
    TARGET_LINE=$(echo "$RESULT_NAME" | grep -i "PVC Pipe Life Cycle" | head -1)
    
    if [ -n "$TARGET_LINE" ]; then
        PROCESS_FOUND="true"
        PROCESS_ID=$(echo "$TARGET_LINE" | awk '{print $1}')
        PROCESS_NAME=$(echo "$TARGET_LINE" | cut -d'|' -f2- | xargs)
        echo "Found Process: $PROCESS_NAME (ID: $PROCESS_ID)"
        
        # Query 2: Get Exchanges for this Process
        # We need Amount and Flow Name
        QUERY_EXCHANGES="SELECT e.AMOUNT, f.NAME FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROCESS_ID;"
        RESULT_EXCHANGES=$(derby_query "$ACTIVE_DB" "$QUERY_EXCHANGES")
        
        # Convert Derby output to JSON array of objects {"amount": X, "flow": "Y"}
        # Skip header lines, filter for data lines
        # Derby output usually separates columns with spaces or pipes depending on formatting, 
        # but pure ij output is often fixed width or pipe separated.
        # We'll use python to parse the raw text reliably.
        
        EXCHANGES_JSON=$(python3 -c "
import sys, json, re
lines = sys.stdin.readlines()
data = []
for line in lines:
    # Skip headers/empty lines (simple heuristic: look for pipe or numbers)
    # Typical ij output: '   10.0            |Some Flow Name    '
    if '|' in line and 'AMOUNT' not in line and '---' not in line:
        parts = line.split('|')
        if len(parts) >= 2:
            try:
                amt = float(parts[0].strip())
                flow = parts[1].strip()
                data.append({'amount': amt, 'flow': flow})
            except:
                pass
print(json.dumps(data))
" <<< "$RESULT_EXCHANGES")
    fi
else
    echo "No active database found."
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp)
cat <<EOF > "$TEMP_JSON"
{
  "output_exists": $OUTPUT_EXISTS,
  "output_size": $OUTPUT_SIZE,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "process_found": $PROCESS_FOUND,
  "process_id": "$PROCESS_ID",
  "exchanges": $EXCHANGES_JSON,
  "screenshot_path": "/tmp/task_final.png",
  "task_duration": $((TASK_END - TASK_START))
}
EOF

export_json_result "/tmp/task_result.json" < "$TEMP_JSON"
rm "$TEMP_JSON"