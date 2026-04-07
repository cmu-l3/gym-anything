#!/bin/bash
# Export script for Regionalized Supply Chain Config task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Regionalized Supply Chain Result ==="

# 1. Capture final visual state
take_screenshot /tmp/task_end_screenshot.png

# 2. Check Output File
OUTPUT_FILE="/home/ga/LCA_Results/regional_boxes_lcia.csv"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Database Verification (The Core Check)
# We need to query the Derby database to see if the links (Default Providers) were set correctly.
# This requires finding the active database and running a SQL query.

close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (likely the one with imported USLCI)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE_MB=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE_MB:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE_MB:-0}"
        ACTIVE_DB="$db_path"
    fi
done

DB_QUERY_RESULT=""
PS_COUNT=0

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 10 ]; then
    echo "Checking database at: $ACTIVE_DB"
    
    # Check if Product System was created
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    
    # Query for the specific Regional Links
    # We join TBL_EXCHANGES with TBL_PROCESSES to find:
    # Source Process Name (Box or Linerboard) -> Exchange (Electricity) -> Default Provider Name (WECC or SERC)
    
    SQL_QUERY="
    SELECT 
        CAST(src.NAME AS VARCHAR(128)) AS Source, 
        CAST(prov.NAME AS VARCHAR(128)) AS Provider 
    FROM TBL_EXCHANGES ex 
    JOIN TBL_PROCESSES src ON ex.F_OWNER = src.ID 
    JOIN TBL_PROCESSES prov ON ex.F_DEFAULT_PROVIDER = prov.ID 
    WHERE 
        (LOWER(src.NAME) LIKE '%corrugated%box%' OR LOWER(src.NAME) LIKE '%linerboard%') 
        AND LOWER(prov.NAME) LIKE '%electricity%';
    "
    
    # Run query and capture output
    # derby_query function is in task_utils.sh
    DB_QUERY_RESULT=$(derby_query "$ACTIVE_DB" "$SQL_QUERY" 2>/dev/null)
else
    echo "No valid database found to verify."
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ps_count": ${PS_COUNT:-0},
    "db_query_result": $(echo "$DB_QUERY_RESULT" | jq -R -s '.'),
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"