#!/bin/bash
# Export script for Register Health Facility task

echo "=== Exporting Register Health Facility Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2024-01-01T00:00:00")
INITIAL_OU_COUNT=$(cat /tmp/initial_ou_count 2>/dev/null || echo "0")

echo "Searching for 'Makonthi MCHP' in DHIS2..."

# Query the specific org unit with extensive fields for verification
# We ask for ancestors to verify it's under Bombali
# We ask for organisationUnitGroups to verify group assignment
OU_DATA=$(dhis2_api "organisationUnits?filter=name:eq:Makonthi%20MCHP&fields=id,name,shortName,openingDate,created,coordinates,geometry,parent[id,name],ancestors[id,name],organisationUnitGroups[id,name]&paging=false" 2>/dev/null | \
python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
    units = data.get('organisationUnits', [])
    
    if not units:
        print(json.dumps({'found': False}))
    else:
        u = units[0]
        # Check ancestors for Bombali
        ancestors = u.get('ancestors', [])
        bombali_in_ancestors = any('Bombali' in a.get('name', '') for a in ancestors)
        
        # Format output
        result = {
            'found': True,
            'id': u.get('id'),
            'name': u.get('name'),
            'shortName': u.get('shortName'),
            'openingDate': u.get('openingDate'),
            'created': u.get('created'),
            'parent_name': u.get('parent', {}).get('name', ''),
            'is_under_bombali': bombali_in_ancestors,
            'group_count': len(u.get('organisationUnitGroups', [])),
            'groups': [g.get('name') for g in u.get('organisationUnitGroups', [])],
            'geometry': u.get('geometry') or u.get('coordinates')
        }
        print(json.dumps(result))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null)

echo "Org Unit Data:"
echo "$OU_DATA" | python3 -m json.tool 2>/dev/null || echo "$OU_DATA"

# Get current total count
CURRENT_OU_COUNT=$(dhis2_api "organisationUnits?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")

echo "Org Unit Counts: Initial=$INITIAL_OU_COUNT, Current=$CURRENT_OU_COUNT"

# Write result JSON
cat > /tmp/register_health_facility_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_ou_count": $INITIAL_OU_COUNT,
    "current_ou_count": $CURRENT_OU_COUNT,
    "ou_data": $OU_DATA,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

echo "Result saved to /tmp/register_health_facility_result.json"
echo "=== Export Complete ==="