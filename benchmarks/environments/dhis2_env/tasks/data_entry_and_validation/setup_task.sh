#!/bin/bash
# Setup script for Data Entry and Validation task

echo "=== Setting up Data Entry and Validation Task ==="

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

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 6); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Find the organisationunitid for Ngelehun CHC (uid: DiszpKrYNg8)
echo "Looking up Ngelehun CHC organisation unit..."
OU_ID=$(dhis2_query "SELECT organisationunitid FROM organisationunit WHERE uid='DiszpKrYNg8'" 2>/dev/null | tr -d ' \n')
if [ -z "$OU_ID" ]; then
    # Try by name if UID lookup fails
    OU_ID=$(dhis2_query "SELECT organisationunitid FROM organisationunit WHERE name ILIKE 'Ngelehun%CHC%' LIMIT 1" 2>/dev/null | tr -d ' \n')
fi
echo "$OU_ID" > /tmp/ngelehun_ou_id
echo "Ngelehun CHC organisationunitid: $OU_ID"

# Find period ID for October 2023 (periodtype = monthly, iso = 202310)
echo "Looking up October 2023 period..."
PERIOD_ID=$(dhis2_query "
    SELECT p.periodid
    FROM period p
    JOIN periodtype pt ON p.periodtypeid = pt.periodtypeid
    WHERE pt.name = 'Monthly'
    AND p.startdate = '2023-10-01'
    LIMIT 1
" 2>/dev/null | tr -d ' \n')

if [ -z "$PERIOD_ID" ]; then
    # Try alternative query
    PERIOD_ID=$(dhis2_query "
        SELECT periodid FROM period
        WHERE startdate = '2023-10-01' AND enddate = '2023-10-31'
        LIMIT 1
    " 2>/dev/null | tr -d ' \n')
fi
echo "$PERIOD_ID" > /tmp/oct2023_period_id
echo "October 2023 period id: $PERIOD_ID"

# Record initial data value count for this specific org unit and period
if [ -n "$OU_ID" ] && [ -n "$PERIOD_ID" ]; then
    INITIAL_DV_COUNT=$(dhis2_query "
        SELECT COUNT(*) FROM datavalue
        WHERE sourceid = $OU_ID AND periodid = $PERIOD_ID
    " 2>/dev/null | tr -d ' \n' || echo "0")
else
    INITIAL_DV_COUNT="0"
fi
echo "$INITIAL_DV_COUNT" > /tmp/initial_datavalue_count_oct2023
echo "Initial data values for Ngelehun CHC Oct 2023: $INITIAL_DV_COUNT"

# Also record total data value count for this org unit (any period)
if [ -n "$OU_ID" ]; then
    INITIAL_TOTAL_DV=$(dhis2_query "
        SELECT COUNT(*) FROM datavalue WHERE sourceid = $OU_ID
    " 2>/dev/null | tr -d ' \n' || echo "0")
else
    INITIAL_TOTAL_DV="0"
fi
echo "$INITIAL_TOTAL_DV" > /tmp/initial_total_datavalue_count
echo "Total initial data values for Ngelehun CHC: $INITIAL_TOTAL_DV"

# Check completedatasetregistration for October 2023 (baseline)
if [ -n "$OU_ID" ] && [ -n "$PERIOD_ID" ]; then
    INITIAL_COMPLETE=$(dhis2_query "
        SELECT COUNT(*) FROM completedatasetregistration
        WHERE sourceid = $OU_ID AND periodid = $PERIOD_ID
    " 2>/dev/null | tr -d ' \n' || echo "0")
else
    INITIAL_COMPLETE="0"
fi
echo "$INITIAL_COMPLETE" > /tmp/initial_complete_registration
echo "Initial completedatasetregistration for Oct 2023: $INITIAL_COMPLETE"

# Ensure Firefox is running and pointing to DHIS2
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Summary ==="
echo "  Target org unit: Ngelehun CHC (UID: DiszpKrYNg8, DB ID: $OU_ID)"
echo "  Target period: October 2023 (DB ID: $PERIOD_ID)"
echo "  Initial data values: $INITIAL_DV_COUNT"
echo "  Initial completions: $INITIAL_COMPLETE"
echo ""
echo "=== Data Entry and Validation Task Setup Complete ==="
