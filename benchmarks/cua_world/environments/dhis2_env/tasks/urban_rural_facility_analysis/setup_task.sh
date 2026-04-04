#!/bin/bash
# Setup script for Urban Rural Facility Analysis task

echo "=== Setting up Urban Rural Facility Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for API
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
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
    echo "DHIS2 not ready (HTTP $HTTP_CODE), waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# Clean up any previous attempts (Anti-Gaming / Clean State)
# We check if the groups already exist (from a previous run) and delete them to ensure the agent actually does the work
echo "Cleaning up potential pre-existing metadata..."

# Find and delete 'Facility Location' Group Set
GROUP_SET_ID=$(dhis2_api "organisationUnitGroupSets?filter=name:eq:Facility+Location&fields=id" 2>/dev/null | jq -r '.organisationUnitGroupSets[0].id // empty')
if [ -n "$GROUP_SET_ID" ]; then
    echo "Deleting existing group set: $GROUP_SET_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/organisationUnitGroupSets/$GROUP_SET_ID" > /dev/null
fi

# Find and delete 'Urban Facilities' and 'Rural Facilities' Groups
for group in "Urban Facilities" "Rural Facilities"; do
    GROUP_ID=$(dhis2_api "organisationUnitGroups?filter=name:eq:${group// /+}&fields=id" 2>/dev/null | jq -r '.organisationUnitGroups[0].id // empty')
    if [ -n "$GROUP_ID" ]; then
        echo "Deleting existing group: $group ($GROUP_ID)"
        curl -s -u admin:district -X DELETE "http://localhost:8080/api/organisationUnitGroups/$GROUP_ID" > /dev/null
    fi
done

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 5
fi

# Wait and maximize
wait_for_window "firefox\|mozilla\|DHIS" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="