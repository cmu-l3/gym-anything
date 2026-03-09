#!/bin/bash
echo "=== Setting up Intervention Cohort Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Fallback API function if not sourced
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Wait for DHIS2 availability
echo "Checking DHIS2 health..."
wait_for_dhis2_readiness() {
    for i in {1..30}; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" | grep -q "200\|401"; then
            echo "DHIS2 is ready."
            return 0
        fi
        sleep 2
    done
    echo "DHIS2 not responding."
    return 1
}
wait_for_dhis2_readiness

# CLEANUP: Remove artifacts from previous runs to prevent false positives
echo "Cleaning up previous task artifacts..."

# 1. Delete Visualization
VIZ_ID=$(dhis2_api "visualizations?filter=name:eq:Pilot+vs+Control+Malaria+2023&fields=id" | jq -r '.visualizations[0].id // empty')
if [ -n "$VIZ_ID" ]; then
    echo "Deleting existing visualization: $VIZ_ID"
    dhis2_api "visualizations/$VIZ_ID" "DELETE"
fi

# 2. Delete Group Set
SET_ID=$(dhis2_api "organisationUnitGroupSets?filter=name:eq:Malaria+Pilot+Status&fields=id" | jq -r '.organisationUnitGroupSets[0].id // empty')
if [ -n "$SET_ID" ]; then
    echo "Deleting existing group set: $SET_ID"
    dhis2_api "organisationUnitGroupSets/$SET_ID" "DELETE"
fi

# 3. Delete Groups
GROUP1_ID=$(dhis2_api "organisationUnitGroups?filter=name:eq:Malaria+Pilot+Sites&fields=id" | jq -r '.organisationUnitGroups[0].id // empty')
if [ -n "$GROUP1_ID" ]; then
    echo "Deleting existing pilot group: $GROUP1_ID"
    dhis2_api "organisationUnitGroups/$GROUP1_ID" "DELETE"
fi

GROUP2_ID=$(dhis2_api "organisationUnitGroups?filter=name:eq:Malaria+Control+Sites&fields=id" | jq -r '.organisationUnitGroups[0].id // empty')
if [ -n "$GROUP2_ID" ]; then
    echo "Deleting existing control group: $GROUP2_ID"
    dhis2_api "organisationUnitGroups/$GROUP2_ID" "DELETE"
fi

# Record start time
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_iso.txt

# Record initial Analytics Table update time
INITIAL_ANALYTICS_TIME=$(dhis2_api "system/info" | jq -r '.lastAnalyticsTableSuccess // ""')
echo "$INITIAL_ANALYTICS_TIME" > /tmp/initial_analytics_time.txt
echo "Initial analytics time: $INITIAL_ANALYTICS_TIME"

# Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
if wait_for_window "firefox\|mozilla\|DHIS" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="