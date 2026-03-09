#!/bin/bash
# Export script for EmOC Org Unit Classification task

echo "=== Exporting EmOC Task Result ==="

source /workspace/scripts/task_utils.sh

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

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
INITIAL_GROUPS=$(cat /tmp/initial_group_count 2>/dev/null || echo "0")
INITIAL_SETS=$(cat /tmp/initial_set_count 2>/dev/null || echo "0")

# 1. Fetch created Organisation Unit Groups
echo "Fetching Org Unit Groups..."
GROUPS_JSON=$(dhis2_api "organisationUnitGroups?fields=id,name,shortName,created,organisationUnits[id,name]&filter=name:ilike:EmOC&paging=false" 2>/dev/null)

# 2. Fetch created Organisation Unit Group Sets
echo "Fetching Org Unit Group Sets..."
SETS_JSON=$(dhis2_api "organisationUnitGroupSets?fields=id,name,shortName,created,dataDimension,organisationUnitGroups[id,name]&filter=name:ilike:EmOC&paging=false" 2>/dev/null)

# 3. Process data into result JSON using Python
echo "Processing results..."
python3 << PYEOF > /tmp/emoc_task_result.json
import json
import sys
from datetime import datetime

try:
    groups_data = json.loads('''$GROUPS_JSON''')
    sets_data = json.loads('''$SETS_JSON''')
    task_start_iso = '$TASK_START_ISO'
    initial_groups = int('$INITIAL_GROUPS')
    initial_sets = int('$INITIAL_SETS')

    # Helper to parse date
    def parse_date(d_str):
        if not d_str: return datetime.min
        try:
            return datetime.fromisoformat(d_str.replace('Z', '+00:00'))
        except:
            return datetime.min

    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime.min

    # Filter groups created after task start
    new_groups = []
    for g in groups_data.get('organisationUnitGroups', []):
        created = parse_date(g.get('created'))
        if created >= task_start:
            new_groups.append({
                'id': g.get('id'),
                'name': g.get('name'),
                'shortName': g.get('shortName'),
                'member_count': len(g.get('organisationUnits', [])),
                'members': [ou.get('name') for ou in g.get('organisationUnits', [])]
            })

    # Filter sets created after task start
    new_sets = []
    for s in sets_data.get('organisationUnitGroupSets', []):
        created = parse_date(s.get('created'))
        if created >= task_start:
            new_sets.append({
                'id': s.get('id'),
                'name': s.get('name'),
                'dataDimension': s.get('dataDimension', False),
                'group_count': len(s.get('organisationUnitGroups', [])),
                'groups': [g.get('name') for g in s.get('organisationUnitGroups', [])]
            })

    result = {
        'task_start': task_start_iso,
        'initial_groups_count': initial_groups,
        'initial_sets_count': initial_sets,
        'created_groups': new_groups,
        'created_sets': new_sets,
        'groups_found_count': len(new_groups),
        'sets_found_count': len(new_sets)
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))
PYEOF

echo "Result saved to /tmp/emoc_task_result.json"
cat /tmp/emoc_task_result.json
echo "=== Export Complete ==="