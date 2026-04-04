#!/bin/bash
echo "=== Exporting Create Organic Depot Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the created storage location
# We look for a record created AFTER task start with the expected name
# Storage locations in Ekylibre are often stored in 'entities' with type 'Depot' or similar,
# or sometimes just generic entities linked to storage. We query broadly for the name.

echo "Querying database for 'Silo Bio 01'..."

# Fetch details of the depot if it exists
# We get ID, Name, Code (if exists), Type, and Created_At timestamp
DB_RESULT=$(ekylibre_db_query "
    SELECT id, name, code, type, EXTRACT(EPOCH FROM created_at)::int 
    FROM entities 
    WHERE name ILIKE 'Silo Bio 01' 
    ORDER BY created_at DESC LIMIT 1;
")

# If empty, try 'products' table just in case (older schema versions used Product/Depot inheritance)
if [ -z "$DB_RESULT" ]; then
    DB_RESULT=$(ekylibre_db_query "
        SELECT id, name, work_number, type, EXTRACT(EPOCH FROM created_at)::int 
        FROM products 
        WHERE name ILIKE 'Silo Bio 01' 
        ORDER BY created_at DESC LIMIT 1;
    ")
fi

# Parse the result
DEPOT_FOUND="false"
DEPOT_NAME=""
DEPOT_CODE=""
DEPOT_TYPE=""
DEPOT_CREATED_AT="0"

if [ -n "$DB_RESULT" ]; then
    DEPOT_FOUND="true"
    # Parse pipe-separated values (psql default with -A) or whatever format ekylibre_db_query outputs
    # ekylibre_db_query uses -A -t (unaligned, tuples only), separator is pipe |
    
    IFS='|' read -r ID NAME CODE TYPE CREATED_AT <<< "$DB_RESULT"
    
    DEPOT_NAME="$NAME"
    DEPOT_CODE="$CODE"
    DEPOT_TYPE="$TYPE"
    DEPOT_CREATED_AT="$CREATED_AT"
fi

# Determine if created during task
CREATED_DURING_TASK="false"
if [ "$DEPOT_FOUND" = "true" ] && [ "$DEPOT_CREATED_AT" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "depot_found": $DEPOT_FOUND,
    "depot_name": "$DEPOT_NAME",
    "depot_code": "$DEPOT_CODE",
    "depot_type": "$DEPOT_TYPE",
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="