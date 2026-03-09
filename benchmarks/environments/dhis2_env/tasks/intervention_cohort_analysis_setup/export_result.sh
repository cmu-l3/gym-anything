#!/bin/bash
echo "=== Exporting Results for Intervention Cohort Analysis ==="

source /workspace/scripts/task_utils.sh

# Fallbacks
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ANALYTICS_TIME=$(cat /tmp/initial_analytics_time.txt 2>/dev/null || echo "")

# 1. Check Organisation Unit Groups
echo "Exporting Org Unit Groups..."
GROUPS_JSON=$(dhis2_api "organisationUnitGroups?filter=name:ilike:Malaria&fields=id,name,created,organisationUnits[id,name]&paging=false")

# 2. Check Organisation Unit Group Sets
echo "Exporting Org Unit Group Sets..."
SETS_JSON=$(dhis2_api "organisationUnitGroupSets?filter=name:ilike:Malaria&fields=id,name,created,organisationUnitGroups[id,name]&paging=false")

# 3. Check Visualizations
echo "Exporting Visualizations..."
# Fetch visualization and its column/row dimensions to verify the group set is used
VIZ_JSON=$(dhis2_api "visualizations?filter=name:ilike:Pilot&fields=id,name,created,columns[dimension,items],rows[dimension,items],filters[dimension,items]&paging=false")

# 4. Check Analytics Update Time
echo "Checking Analytics Table status..."
CURRENT_ANALYTICS_TIME=$(dhis2_api "system/info" | jq -r '.lastAnalyticsTableSuccess // ""')

# Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_analytics_time": "$INITIAL_ANALYTICS_TIME",
    "current_analytics_time": "$CURRENT_ANALYTICS_TIME",
    "groups_data": $GROUPS_JSON,
    "group_sets_data": $SETS_JSON,
    "visualizations_data": $VIZ_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete."