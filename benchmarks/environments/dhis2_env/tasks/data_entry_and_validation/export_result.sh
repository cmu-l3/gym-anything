#!/bin/bash
# Export script for Data Entry and Validation task

echo "=== Exporting Data Entry and Validation Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' ' || echo "0")

# Read baseline values
OU_ID=$(cat /tmp/ngelehun_ou_id 2>/dev/null | tr -d ' \n' || echo "")
PERIOD_ID=$(cat /tmp/oct2023_period_id 2>/dev/null | tr -d ' \n' || echo "")
INITIAL_DV_COUNT=$(cat /tmp/initial_datavalue_count_oct2023 2>/dev/null | tr -d ' ' || echo "0")
INITIAL_COMPLETE=$(cat /tmp/initial_complete_registration 2>/dev/null | tr -d ' ' || echo "0")

echo "Baseline: ou_id=$OU_ID, period_id=$PERIOD_ID, initial_dvs=$INITIAL_DV_COUNT, initial_complete=$INITIAL_COMPLETE"

# If we couldn't find the org unit ID in setup, try again
if [ -z "$OU_ID" ]; then
    OU_ID=$(dhis2_query "SELECT organisationunitid FROM organisationunit WHERE uid='DiszpKrYNg8'" 2>/dev/null | tr -d ' \n')
    echo "Re-queried OU ID: $OU_ID"
fi

# If we couldn't find period ID, try again
if [ -z "$PERIOD_ID" ]; then
    PERIOD_ID=$(dhis2_query "
        SELECT periodid FROM period
        WHERE startdate = '2023-10-01' AND enddate = '2023-10-31'
        LIMIT 1
    " 2>/dev/null | tr -d ' \n')
    echo "Re-queried period ID: $PERIOD_ID"
fi

# Query current data values for Ngelehun CHC, October 2023
CURRENT_DV_DATA="[]"
CURRENT_DV_COUNT=0
NEW_DV_COUNT=0
DV_VALUES_OK=0

if [ -n "$OU_ID" ] && [ -n "$PERIOD_ID" ]; then
    echo "Querying data values for Ngelehun CHC, October 2023..."

    # Get data values entered after task start (using timestamp)
    DV_QUERY_RESULT=$(dhis2_query "
        SELECT
            dv.value,
            dv.created,
            de.name as element_name
        FROM datavalue dv
        JOIN dataelement de ON dv.dataelementid = de.dataelementid
        WHERE dv.sourceid = $OU_ID
          AND dv.periodid = $PERIOD_ID
        ORDER BY dv.created DESC
        LIMIT 50
    " 2>/dev/null)

    echo "Data values for Oct 2023:"
    echo "$DV_QUERY_RESULT" | head -20

    CURRENT_DV_COUNT=$(dhis2_query "
        SELECT COUNT(*) FROM datavalue
        WHERE sourceid = $OU_ID AND periodid = $PERIOD_ID
    " 2>/dev/null | tr -d ' \n' || echo "0")

    # Count new data values added after task start
    # Convert task start epoch to a timestamp DHIS2 can compare
    TASK_START_TS=$(date -d "@$TASK_START_EPOCH" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                   python3 -c "import datetime; print(datetime.datetime.fromtimestamp($TASK_START_EPOCH).strftime('%Y-%m-%d %H:%M:%S'))" 2>/dev/null || \
                   echo "2020-01-01 00:00:00")

    NEW_DV_COUNT=$(dhis2_query "
        SELECT COUNT(*) FROM datavalue
        WHERE sourceid = $OU_ID
          AND periodid = $PERIOD_ID
          AND created >= '$TASK_START_TS'::timestamp
    " 2>/dev/null | tr -d ' \n' || echo "0")

    echo "Current DV count: $CURRENT_DV_COUNT, New after task start: $NEW_DV_COUNT"

    # Also count DVs updated after task start (some DHIS2 versions use lastupdated)
    NEW_DV_UPDATED_COUNT=$(dhis2_query "
        SELECT COUNT(*) FROM datavalue
        WHERE sourceid = $OU_ID
          AND periodid = $PERIOD_ID
          AND lastupdated >= '$TASK_START_TS'::timestamp
    " 2>/dev/null | tr -d ' \n' || echo "0")
    echo "DVs updated after task start: $NEW_DV_UPDATED_COUNT"

    # Use whichever is larger
    if [ "${NEW_DV_UPDATED_COUNT:-0}" -gt "${NEW_DV_COUNT:-0}" ] 2>/dev/null; then
        NEW_DV_COUNT=$NEW_DV_UPDATED_COUNT
    fi

    # Check if values are plausible (between 0 and 10000)
    DV_VALUES_OK=$(dhis2_query "
        SELECT COUNT(*) FROM datavalue
        WHERE sourceid = $OU_ID
          AND periodid = $PERIOD_ID
          AND value ~ '^[0-9]+$'
          AND value::integer >= 0
          AND value::integer <= 10000
    " 2>/dev/null | tr -d ' \n' || echo "0")
    echo "Data values within plausible range (0-10000): $DV_VALUES_OK"
fi

# Check completedatasetregistration for October 2023
COMPLETE_AFTER_START=0
COMPLETE_EXISTS=0
if [ -n "$OU_ID" ] && [ -n "$PERIOD_ID" ]; then
    COMPLETE_EXISTS=$(dhis2_query "
        SELECT COUNT(*) FROM completedatasetregistration
        WHERE sourceid = $OU_ID AND periodid = $PERIOD_ID
    " 2>/dev/null | tr -d ' \n' || echo "0")

    TASK_START_TS=$(date -d "@$TASK_START_EPOCH" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                   python3 -c "import datetime; print(datetime.datetime.fromtimestamp($TASK_START_EPOCH).strftime('%Y-%m-%d %H:%M:%S'))" 2>/dev/null || \
                   echo "2020-01-01 00:00:00")

    COMPLETE_AFTER_START=$(dhis2_query "
        SELECT COUNT(*) FROM completedatasetregistration
        WHERE sourceid = $OU_ID
          AND periodid = $PERIOD_ID
          AND date >= '$TASK_START_TS'::timestamp
    " 2>/dev/null | tr -d ' \n' || echo "0")
fi
echo "Complete registrations: exists=$COMPLETE_EXISTS, after_task_start=$COMPLETE_AFTER_START"

# Write result JSON
cat > /tmp/data_entry_and_validation_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "org_unit_id": "$OU_ID",
    "period_id": "$PERIOD_ID",
    "initial_datavalue_count": ${INITIAL_DV_COUNT:-0},
    "current_datavalue_count": ${CURRENT_DV_COUNT:-0},
    "new_datavalue_count": ${NEW_DV_COUNT:-0},
    "values_in_plausible_range": ${DV_VALUES_OK:-0},
    "complete_registration_exists": ${COMPLETE_EXISTS:-0},
    "complete_registration_after_start": ${COMPLETE_AFTER_START:-0},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/data_entry_and_validation_result.json 2>/dev/null || true
echo ""
echo "Result JSON saved to /tmp/data_entry_and_validation_result.json"
cat /tmp/data_entry_and_validation_result.json
echo ""
echo "=== Export Complete ==="
