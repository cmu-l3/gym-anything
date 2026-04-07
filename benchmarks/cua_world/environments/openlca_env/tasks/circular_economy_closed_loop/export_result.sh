#!/bin/bash
# Export script for Circular Economy Closed-Loop task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Circular Economy Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Basic Variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"

# 3. Check for Result File (CSV)
RESULT_FILE=""
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
CONTENT_GWP="false"

# Find newest CSV in results dir
CANDIDATE=$(ls -t "$RESULTS_DIR"/*.csv 2>/dev/null | head -1)

if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ]; then
    RESULT_FILE="$CANDIDATE"
    FILE_SIZE=$(stat -c %s "$CANDIDATE" 2>/dev/null || echo "0")
    
    # Check timestamp
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check content for "Global Warming" or "GWP"
    if grep -qi "Global Warming\|GWP\|CO2\|climate" "$CANDIDATE"; then
        CONTENT_GWP="true"
    fi
fi

# 4. Database Topology Check (The Hard Part)
# We need to verify the loop structure in the Derby DB.
# We will query table counts and specific names.

# Close OpenLCA to unlock Derby
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find the active database (largest one likely contains USLCI)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_NAMES=""
FLOW_NAMES=""
PRODUCT_SYSTEM_COUNT=0
LOOP_EVIDENCE="false"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database: $ACTIVE_DB"
    
    # Query Process Names (looking for Manufacturing, Recycling, Use)
    # We fetch names that match our keywords
    PROCESS_QUERY="SELECT NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%manufactur%' OR LOWER(NAME) LIKE '%recycl%' OR LOWER(NAME) LIKE '%use%' OR LOWER(NAME) LIKE '%collect%';"
    PROCESS_NAMES=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY" 2>/dev/null)
    
    # Query Flow Names
    FLOW_QUERY="SELECT NAME FROM TBL_FLOWS WHERE LOWER(NAME) LIKE '%rpet%' OR LOWER(NAME) LIKE '%scrap%' OR LOWER(NAME) LIKE '%flake%';"
    FLOW_NAMES=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY" 2>/dev/null)
    
    # Query Product System Count
    PRODUCT_SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    
    # Advanced: Check for Exchange Linkage (Heuristic)
    # If we have processes and a product system, and the DB size increased, we assume linkage attempt.
    # A true SQL query for the loop A->B->C->A is too complex for this script, 
    # so we rely on process existence + product system existence + VLM.
fi

# 5. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "result_file_exists": $([ -n "$RESULT_FILE" ] && echo "true" || echo "false"),
    "result_file_path": "$RESULT_FILE",
    "result_file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "content_has_gwp": $CONTENT_GWP,
    "db_found": $([ -n "$ACTIVE_DB" ] && echo "true" || echo "false"),
    "product_system_count": ${PRODUCT_SYSTEM_COUNT:-0},
    "process_names_dump": "$(echo "$PROCESS_NAMES" | tr '\n' ' ' | sed 's/"/\\"/g')",
    "flow_names_dump": "$(echo "$FLOW_NAMES" | tr '\n' ' ' | sed 's/"/\\"/g')"
}
EOF

# 6. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="