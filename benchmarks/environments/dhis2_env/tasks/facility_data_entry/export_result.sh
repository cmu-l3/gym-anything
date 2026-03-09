#!/bin/bash
# Export script for Facility Data Entry task

echo "=== Exporting Facility Data Entry Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Task Info
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Query Database for Resulting Data
# We look for Ngelehun CHC and Jan 2024
echo "Querying database for submitted data..."

ORG_UNIT_ID=$(dhis2_query "SELECT organisationunitid FROM organisationunit WHERE name ILIKE '%Ngelehun CHC%' LIMIT 1" | tr -d '[:space:]')
PERIOD_ID=$(dhis2_query "SELECT periodid FROM period WHERE iso = '202401' LIMIT 1" | tr -d '[:space:]')

DATA_VALUES_JSON="[]"
COMPLETION_STATUS="false"

if [ -n "$ORG_UNIT_ID" ] && [ -n "$PERIOD_ID" ]; then
    # Fetch data values
    # We join with dataelement to get names for easier verification
    DATA_QUERY="
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT 
                de.name as data_element,
                dv.value,
                dv.lastupdated
            FROM datavalue dv
            JOIN dataelement de ON dv.dataelementid = de.dataelementid
            WHERE dv.sourceid = $ORG_UNIT_ID 
            AND dv.periodid = $PERIOD_ID
        ) t;
    "
    DATA_VALUES_JSON=$(dhis2_query "$DATA_QUERY" | sed 's/^+//g' || echo "[]")
    
    # Handle empty result (psql returns empty string or NULL)
    if [ -z "$DATA_VALUES_JSON" ] || [ "$DATA_VALUES_JSON" == " " ]; then
        DATA_VALUES_JSON="[]"
    fi

    # Check completion status
    COMPLETION_QUERY="SELECT COUNT(*) FROM completedatasetregistration WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_ID"
    COMPLETION_COUNT=$(dhis2_query "$COMPLETION_QUERY" | tr -d '[:space:]')
    if [ "$COMPLETION_COUNT" -gt "0" ]; then
        COMPLETION_STATUS="true"
    fi
else
    echo "Could not find OrgUnit or Period in DB to verify."
fi

# 4. Construct Result JSON
# Use Python to handle proper JSON construction to avoid escaping issues
python3 << EOF
import json
import time

try:
    data_values = $DATA_VALUES_JSON
    if data_values is None:
        data_values = []
except:
    data_values = []

result = {
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "org_unit_found": bool("$ORG_UNIT_ID"),
    "period_found": bool("$PERIOD_ID"),
    "data_values": data_values,
    "is_completed": $COMPLETION_STATUS,
    "export_timestamp": time.time()
}

with open('/tmp/facility_data_entry_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# 5. Cleanup / Permissions
chmod 666 /tmp/facility_data_entry_result.json 2>/dev/null || true

echo "Result exported to /tmp/facility_data_entry_result.json"
cat /tmp/facility_data_entry_result.json
echo ""
echo "=== Export Complete ==="