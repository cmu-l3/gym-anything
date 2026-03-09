#!/bin/bash
# Setup script for Min-Max Data Entry Bounds task

echo "=== Setting up Min-Max Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for dhis2_query if utils not fully loaded
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
fi

if ! type take_screenshot &>/dev/null; then
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

# Record initial Min-Max value count for Bombali district
# This establishes the baseline to detect if new values are generated
echo "Recording initial min-max record count for Bombali..."
INITIAL_COUNT=$(dhis2_query "
    SELECT COUNT(*) 
    FROM minmaxdataelement mmd
    JOIN organisationunit ou ON mmd.sourceid = ou.organisationunitid
    WHERE ou.path LIKE '%/O6uvpzGd5pu%' OR ou.name ILIKE '%Bombali%'
" 2>/dev/null | tr -d ' ' || echo "0")

# Note: O6uvpzGd5pu is the UID for Bombali in Sierra Leone demo DB
echo "$INITIAL_COUNT" > /tmp/initial_minmax_count
echo "Initial min-max count: $INITIAL_COUNT"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate to home if already open
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

# Focus window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Remove summary file if it exists from previous run
rm -f /home/ga/Desktop/minmax_config_summary.txt

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="