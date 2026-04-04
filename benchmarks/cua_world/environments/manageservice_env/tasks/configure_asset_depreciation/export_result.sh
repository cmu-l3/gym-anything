#!/bin/bash
echo "=== Exporting Asset Depreciation Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Verification
# We need to fetch the depreciation settings for 'Workstation'.
# We extract: Useful Life, Salvage Value, and Method Name.

echo "Querying database for Workstation depreciation settings..."

# JSON construction via SQL to ensure we get a structured result even if empty
# We join producttype -> depreciationinfo -> depreciationmethod
QUERY_SQL="
SELECT row_to_json(t) FROM (
    SELECT 
        p.typename as product_name,
        d.usefullife as useful_life_months,
        d.salvagevalue as salvage_percentage,
        m.methodname as method_name
    FROM producttype p
    JOIN depreciationinfo d ON p.typeid = d.producttypeid
    LEFT JOIN depreciationmethod m ON d.methodid = m.methodid
    WHERE p.typename = 'Workstation'
) t;
"

DB_RESULT=$(sdp_db_exec "$QUERY_SQL")

# If result is empty (no record found), manually create a "not found" JSON
if [ -z "$DB_RESULT" ]; then
    echo "No depreciation record found in DB."
    JSON_CONTENT='{"found": false}'
else
    # The SQL returns a JSON object, but we wrap it to add metadata
    JSON_CONTENT="{\"found\": true, \"data\": $DB_RESULT}"
fi

# 3. Create Final Result JSON
# We include timestamp and app state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f "wrapper" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "app_running": $APP_RUNNING,
    "db_result": $JSON_CONTENT
}
EOF

# 4. Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json