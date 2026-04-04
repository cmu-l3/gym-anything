#!/bin/bash
# Export script for Report Crop Incident task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Report Crop Incident Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_incident_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Result
# We look for incidents created AFTER the task started.
# We join with parcels/zones to get the location name if possible.
# Note: SQL queries depend on Ekylibre schema version. We use a robust query that tries to get relevant IDs.

echo "Querying database for new incidents..."

# This query attempts to fetch the most recent incident details
# We fetch: ID, Created At, Severity, Plot Name (via polymorphic relation or join), Cause Name
# Note: In Ekylibre, 'incidents' usually link to a 'zone' (parcel) and have a 'cause' (lexicon reference)
SQL_QUERY="
WITH recent_incidents AS (
    SELECT 
        i.id,
        i.created_at,
        i.gravity as severity,
        i.zone_id,
        i.cause_name,
        z.name as zone_name
    FROM incidents i
    LEFT JOIN zones z ON i.zone_id = z.id
    WHERE i.created_at > to_timestamp($TASK_START)
    ORDER BY i.created_at DESC
    LIMIT 1
)
SELECT row_to_json(t) FROM recent_incidents t;
"

NEW_INCIDENT_JSON=$(ekylibre_db_query "$SQL_QUERY" 2>/dev/null || echo "")

# If JSON is empty, check count manually
CURRENT_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM incidents" 2>/dev/null || echo "0")

# 4. Check if app was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Prepare Result JSON
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "new_incident_record": ${NEW_INCIDENT_JSON:-null},
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="