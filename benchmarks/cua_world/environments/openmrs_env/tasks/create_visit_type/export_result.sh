#!/bin/bash
echo "=== Exporting Create Visit Type Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Task Variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_visittype_count 2>/dev/null || echo "0")

# 3. Query Database for the Visit Type
# We use direct DB query to get exact fields and creation timestamp
echo "Querying database for 'Telemedicine'..."

# SQL query to get details of the visit type
# Note: visit_type table usually has: visit_type_id, name, description, retired, date_created, uuid
SQL="SELECT name, description, retired, date_created FROM visit_type WHERE name = 'Telemedicine' AND retired = 0;"

# Execute query via helper
DB_RESULT=$(omrs_db_query "$SQL")

# Parse DB result
# Expected format from mysql -N: "Telemedicine	Remote consultation...	0	2023-10-27 10:00:00"
if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    NAME=$(echo "$DB_RESULT" | cut -f1)
    DESCRIPTION=$(echo "$DB_RESULT" | cut -f2)
    RETIRED=$(echo "$DB_RESULT" | cut -f3)
    DATE_CREATED_STR=$(echo "$DB_RESULT" | cut -f4)
    
    # Convert DB timestamp to epoch for comparison
    DATE_CREATED_EPOCH=$(date -d "$DATE_CREATED_STR" +%s 2>/dev/null || echo "0")
else
    FOUND="false"
    NAME=""
    DESCRIPTION=""
    RETIRED=""
    DATE_CREATED_EPOCH="0"
fi

# 4. Get current count via API for secondary verification
CURRENT_COUNT=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_epoch": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "found_in_db": $FOUND,
    "db_record": {
        "name": "$NAME",
        "description": "$DESCRIPTION",
        "retired": "$RETIRED",
        "date_created_epoch": $DATE_CREATED_EPOCH
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json