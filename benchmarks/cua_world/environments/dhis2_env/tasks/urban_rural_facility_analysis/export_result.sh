#!/bin/bash
# Export script for Urban Rural Facility Analysis task

echo "=== Exporting Urban Rural Facility Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Inline fallback
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# 1. Check if Org Unit Groups exist
echo "Checking Org Unit Groups..."
GROUPS_JSON=$(dhis2_api "organisationUnitGroups?filter=name:in:[Urban+Facilities,Rural+Facilities]&fields=id,name,created,organisationUnits[id]" 2>/dev/null)

# 2. Check if Org Unit Group Set exists
echo "Checking Org Unit Group Set..."
GROUP_SETS_JSON=$(dhis2_api "organisationUnitGroupSets?filter=name:eq:Facility+Location&fields=id,name,created,dataDimension,organisationUnitGroups[id]" 2>/dev/null)

# 3. Check specific facility assignments
# Bo Gov Hospital UID: O6uvpzGd5pu
# Ngelehun CHC UID: DiszpKrRYkv
echo "Checking Facility Assignments..."
BO_GOV_GROUPS=$(dhis2_api "organisationUnits/O6uvpzGd5pu?fields=organisationUnitGroups[id,name]" 2>/dev/null)
NGELEHUN_GROUPS=$(dhis2_api "organisationUnits/DiszpKrRYkv?fields=organisationUnitGroups[id,name]" 2>/dev/null)

# 4. Check for Visualization
echo "Checking Visualizations..."
# Fetch visualizations created after task start matching the name pattern
VIZ_JSON=$(dhis2_api "visualizations?filter=displayName:ilike:Urban&fields=id,displayName,created,columnDimensions,rowDimensions,filterDimensions" 2>/dev/null)

# 5. Check System Task History (for Analytics Table generation)
# Note: This is harder to query directly via simple API filters, so we look for system info or notifications
# We will check if the 'lastAnalyticsTableSuccess' is recent in system/info
SYSTEM_INFO=$(dhis2_api "system/info" 2>/dev/null)

# Combine all data into result JSON
cat > /tmp/urban_rural_analysis_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "groups_data": $GROUPS_JSON,
    "group_sets_data": $GROUP_SETS_JSON,
    "bo_gov_groups": $BO_GOV_GROUPS,
    "ngelehun_groups": $NGELEHUN_GROUPS,
    "visualizations_data": $VIZ_JSON,
    "system_info": $SYSTEM_INFO,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/urban_rural_analysis_result.json 2>/dev/null || true
echo "Result JSON saved to /tmp/urban_rural_analysis_result.json"
echo "=== Export Complete ==="