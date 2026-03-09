#!/bin/bash
# Export script for Data Element Groupset Dimension task

echo "=== Exporting Results ==="

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

# 1. Query Data Element Groups
echo "Querying Data Element Groups..."
# We filter by 'Malaria' to narrow it down, then check specific names in Python
GROUPS_JSON=$(dhis2_api "dataElementGroups?filter=name:ilike:Malaria&fields=id,name,dataElements[id,name],created&paging=false" 2>/dev/null)

# 2. Query Data Element Group Sets
echo "Querying Data Element Group Sets..."
GROUPSETS_JSON=$(dhis2_api "dataElementGroupSets?filter=name:ilike:Malaria&fields=id,name,dataDimension,dataElementGroups[id,name],created&paging=false" 2>/dev/null)

# 3. Query Visualizations
echo "Querying Visualizations..."
VIZ_JSON=$(dhis2_api "visualizations?fields=id,name,created&order=created:desc&pageSize=10" 2>/dev/null)

# 4. Parse and combine into a single result JSON
echo "Processing results..."
python3 -c "
import json
import sys
from datetime import datetime

task_start_iso = '$TASK_START_ISO'
try:
    # Basic ISO parsing that handles Z and offsets
    task_start_iso = task_start_iso.replace('Z', '+00:00')
    task_start = datetime.fromisoformat(task_start_iso)
except:
    task_start = datetime(2020, 1, 1)

def is_recent(created_str):
    if not created_str: return False
    try:
        created_str = created_str.replace('Z', '+00:00')
        dt = datetime.fromisoformat(created_str)
        return dt >= task_start
    except:
        return False

try:
    groups_data = json.loads('''$GROUPS_JSON''')
    groupsets_data = json.loads('''$GROUPSETS_JSON''')
    viz_data = json.loads('''$VIZ_JSON''')
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(0)

results = {
    'testing_group_found': False,
    'testing_group_element_count': 0,
    'treatment_group_found': False,
    'treatment_group_element_count': 0,
    'groupset_found': False,
    'groupset_is_dimension': False,
    'groupset_group_count': 0,
    'visualization_found': False,
    'visualization_name': ''
}

# Check Groups
for g in groups_data.get('dataElementGroups', []):
    name = g.get('name', '').lower()
    if 'malaria' in name and 'test' in name:
        results['testing_group_found'] = True
        results['testing_group_element_count'] = len(g.get('dataElements', []))
    if 'malaria' in name and 'treat' in name:
        results['treatment_group_found'] = True
        results['treatment_group_element_count'] = len(g.get('dataElements', []))

# Check Group Set
for gs in groupsets_data.get('dataElementGroupSets', []):
    name = gs.get('name', '').lower()
    if 'malaria' in name and 'programme' in name:
        results['groupset_found'] = True
        results['groupset_is_dimension'] = gs.get('dataDimension', False)
        results['groupset_group_count'] = len(gs.get('dataElementGroups', []))

# Check Visualization
for v in viz_data.get('visualizations', []):
    name = v.get('name', '').lower()
    if is_recent(v.get('created')) and ('malaria' in name or 'programme' in name):
        results['visualization_found'] = True
        results['visualization_name'] = v.get('name')
        break

print(json.dumps(results, indent=2))
" > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON saved."
cat /tmp/task_result.json