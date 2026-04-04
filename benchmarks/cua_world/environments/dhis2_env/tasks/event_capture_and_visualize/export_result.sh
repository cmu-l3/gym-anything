#!/bin/bash
# Export script for Event Capture and Visualize task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Context
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || date -Iseconds)
TASK_START_TS=$(cat /tmp/task_start_timestamp 2>/dev/null || date +%s)
PROG_ID=$(cat /tmp/target_program_id 2>/dev/null)
INITIAL_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")

echo "Task Start: $TASK_START_ISO"
echo "Program ID: $PROG_ID"

# 3. Check for New Events in Database
# We look for events in the program created after task start
# 'programstageinstance' table holds single events
# 'geometry' column holds the coordinates (PostGIS geometry type)
# 'status' column holds 'COMPLETED' or 'ACTIVE'

echo "Querying new events..."
NEW_EVENTS_JSON="[]"

if [ -n "$PROG_ID" ]; then
    # We construct a JSON array directly from SQL for robustness
    # Note: Extracting geometry as GeoJSON or text
    SQL_QUERY="
    SELECT json_agg(row_to_json(t)) FROM (
        SELECT 
            psi.uid, 
            psi.created, 
            psi.status,
            ST_AsText(psi.geometry) as geometry_text,
            (
                SELECT string_agg(pdv.value, ', ') 
                FROM trackedentitydatavalue pdv 
                WHERE pdv.programstageinstanceid = psi.programstageinstanceid
            ) as data_values
        FROM programstageinstance psi
        JOIN program p ON psi.programid = p.programid
        WHERE p.uid = '$PROG_ID'
        AND psi.created >= '$TASK_START_ISO'
    ) t;
    "
    
    NEW_EVENTS_JSON=$(dhis2_query "$SQL_QUERY" | head -n 1)
    
    # If null/empty, set to empty array
    if [ -z "$NEW_EVENTS_JSON" ] || [ "$NEW_EVENTS_JSON" == " " ]; then
        NEW_EVENTS_JSON="[]"
    fi
fi

echo "Found events JSON: ${NEW_EVENTS_JSON:0:100}..." # Print start for debugging

# 4. Check for Visualization
# Query API for visualizations created after task start with matching name
echo "Querying visualizations..."
VIZ_JSON=$(dhis2_api "visualizations?filter=name:ilike:Bo%20Campaign&fields=id,name,type,created,dataDimensionItems" | jq -r '.')

# 5. Check if Data Visualizer app was used (screenshot verification placeholder or process check)
APP_USED=false
if pgrep -f "firefox" > /dev/null; then
    APP_USED=true
fi

# 6. Construct Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start_iso": "$TASK_START_ISO",
    "program_id": "$PROG_ID",
    "initial_event_count": $INITIAL_COUNT,
    "new_events": $NEW_EVENTS_JSON,
    "visualization_query": $VIZ_JSON,
    "app_running": $APP_USED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so python verifier can read it
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json | head -n 20