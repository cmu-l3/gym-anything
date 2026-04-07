#!/bin/bash
set -e
echo "=== Exporting configure_project_type results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 3. Query the Database for the Project Type
echo "--- Querying Database ---"

# Get the Project Type ID and details
# We use psql's -t (tuples only) and -A (no align) to get clean output, using specific delimiters
PT_QUERY="SELECT c_projecttype_id, name, created FROM c_projecttype WHERE name='Winter Garden Prep' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1"
PT_DATA=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|" -c "$PT_QUERY" 2>/dev/null || echo "")

PT_FOUND="false"
PT_ID=""
PT_NAME=""
PT_CREATED=""
PHASES_JSON="[]"

if [ -n "$PT_DATA" ]; then
    PT_FOUND="true"
    PT_ID=$(echo "$PT_DATA" | cut -d'|' -f1)
    PT_NAME=$(echo "$PT_DATA" | cut -d'|' -f2)
    PT_CREATED=$(echo "$PT_DATA" | cut -d'|' -f3)
    
    echo "  Found Project Type: $PT_NAME (ID: $PT_ID)"

    # Get Phases for this Project Type
    # We construct a JSON array manually from the query results to avoid dependency issues inside the container
    PHASES_QUERY="SELECT name, seqno, standardqty FROM c_phase WHERE c_projecttype_id=$PT_ID ORDER BY seqno ASC"
    PHASES_RAW=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|" -c "$PHASES_QUERY" 2>/dev/null || echo "")
    
    # Convert raw pipe-delimited lines to JSON objects
    if [ -n "$PHASES_RAW" ]; then
        PHASES_LIST=""
        while IFS= read -r line; do
            p_name=$(echo "$line" | cut -d'|' -f1)
            p_seq=$(echo "$line" | cut -d'|' -f2)
            p_qty=$(echo "$line" | cut -d'|' -f3)
            
            # Clean up whitespace
            p_name=$(echo "$p_name" | xargs)
            
            # Append to list
            ITEM="{\"name\": \"$p_name\", \"seq\": $p_seq, \"qty\": $p_qty}"
            if [ -z "$PHASES_LIST" ]; then
                PHASES_LIST="$ITEM"
            else
                PHASES_LIST="$PHASES_LIST, $ITEM"
            fi
        done <<< "$PHASES_RAW"
        PHASES_JSON="[$PHASES_LIST]"
    fi
else
    echo "  Project Type 'Winter Garden Prep' not found."
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "project_type_found": $PT_FOUND,
    "project_type_id": "$PT_ID",
    "project_type_name": "$PT_NAME",
    "project_type_created": "$PT_CREATED",
    "phases": $PHASES_JSON
}
EOF

# 6. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="