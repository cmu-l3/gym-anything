#!/bin/bash
echo "=== Exporting create_financial_year result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Result
# We need to find the Year 2030, check its calendar, and count its periods
echo "--- Querying Database ---"

# Get details about the Year 2030
# Returns: C_Year_ID | Calendar_Name | Created_Timestamp | Period_Count
DB_RESULT=$(idempiere_query "
SELECT 
    y.c_year_id,
    c.name as calendar_name,
    EXTRACT(EPOCH FROM y.created) as created_ts,
    (SELECT COUNT(*) FROM c_period p WHERE p.c_year_id = y.c_year_id) as period_count
FROM c_year y
JOIN c_calendar c ON y.c_calendar_id = c.c_calendar_id
WHERE y.fiscalyear = '2030' 
  AND y.ad_client_id = $CLIENT_ID
LIMIT 1;
" 2>/dev/null)

# Parse result (psql output is pipe separated usually if we don't use -A -t properly, 
# but idempiere_query uses -A -t which makes it pipe separated by default)
# Actually idempiere_query uses -t -A, default separator is pipe
echo "DB Result: $DB_RESULT"

YEAR_EXISTS="false"
CALENDAR_NAME=""
CREATED_TS="0"
PERIOD_COUNT="0"

if [ -n "$DB_RESULT" ]; then
    YEAR_EXISTS="true"
    # Split by pipe
    IFS='|' read -r YEAR_ID CALENDAR_NAME CREATED_TS PERIOD_COUNT <<< "$DB_RESULT"
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "year_exists": $YEAR_EXISTS,
    "calendar_name": "$CALENDAR_NAME",
    "created_timestamp": ${CREATED_TS:-0},
    "period_count": ${PERIOD_COUNT:-0},
    "client_id": ${CLIENT_ID:-11},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export Complete ==="