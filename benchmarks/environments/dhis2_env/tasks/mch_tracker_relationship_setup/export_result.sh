#!/bin/bash
# Export script for MCH Tracker Relationship Setup task

echo "=== Exporting MCH Tracker Setup Result ==="

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

echo "Querying newly created metadata..."

# 1. Query for the Attribute
# We filter by name vaguely to catch partial matches, then refine in Python
# Note: DHIS2 2.40 API for attributes
TEA_RESPONSE=$(dhis2_api "trackedEntityAttributes?fields=id,name,shortName,valueType,searchable,created&filter=name:ilike:Mother&paging=false" 2>/dev/null)

# 2. Query for the Relationship Type
# Note: DHIS2 2.40 API for relationship types
# Constraints are complex objects: fromConstraint: { relationshipEntity: "TRACKED_ENTITY_INSTANCE", trackedEntityType: { id: "..." } }
RT_RESPONSE=$(dhis2_api "relationshipTypes?fields=id,name,fromConstraint,toConstraint,created&filter=name:ilike:Mother&paging=false" 2>/dev/null)

# 3. Query Tracked Entity Types to map IDs to Names (for constraint verification)
TET_RESPONSE=$(dhis2_api "trackedEntityTypes?fields=id,displayName&paging=false" 2>/dev/null)

# 4. Process results with Python
echo "Processing results..."
python3 -c "
import json
import sys
from datetime import datetime

def parse_dhis2_date(s):
    if not s: return datetime.min
    s = s.replace('Z', '+00:00')
    return datetime.fromisoformat(s)

try:
    task_start_iso = '$TASK_START_ISO'
    task_start = datetime.fromisoformat(task_start_iso.replace('Z', '+00:00'))
except:
    task_start = datetime(2023, 1, 1)

# Load API responses
try:
    tea_data = json.loads('''$TEA_RESPONSE''')
    rt_data = json.loads('''$RT_RESPONSE''')
    tet_data = json.loads('''$TET_RESPONSE''')
except:
    tea_data = {'trackedEntityAttributes': []}
    rt_data = {'relationshipTypes': []}
    tet_data = {'trackedEntityTypes': []}

# Map TET IDs to Names
tet_map = {t['id']: t['displayName'] for t in tet_data.get('trackedEntityTypes', [])}

# Analyze Attributes
target_tea = None
for tea in tea_data.get('trackedEntityAttributes', []):
    created = parse_dhis2_date(tea.get('created', ''))
    name = tea.get('name', '').lower()
    
    # Check if created/modified after task start
    # Note: 'created' is strictly creation.
    # We look for keywords: 'mother' and 'registration'
    if created >= task_start and 'mother' in name and ('registration' in name or 'reg' in name):
        target_tea = tea
        break

# Analyze Relationship Types
target_rt = None
for rt in rt_data.get('relationshipTypes', []):
    created = parse_dhis2_date(rt.get('created', ''))
    name = rt.get('name', '').lower()
    
    if created >= task_start and 'mother' in name and 'child' in name:
        target_rt = rt
        # Enhance with readable constraint names
        if 'fromConstraint' in target_rt:
            fc = target_rt['fromConstraint']
            tet_id = fc.get('trackedEntityType', {}).get('id')
            fc['trackedEntityTypeName'] = tet_map.get(tet_id, 'Unknown')
            
        if 'toConstraint' in target_rt:
            tc = target_rt['toConstraint']
            tet_id = tc.get('trackedEntityType', {}).get('id')
            tc['trackedEntityTypeName'] = tet_map.get(tet_id, 'Unknown')
        break

result = {
    'attribute_found': target_tea is not None,
    'attribute_data': target_tea,
    'relationship_found': target_rt is not None,
    'relationship_data': target_rt,
    'timestamp': datetime.now().isoformat()
}

with open('/tmp/mch_tracker_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Result processed.')
"

chmod 666 /tmp/mch_tracker_setup_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/mch_tracker_setup_result.json