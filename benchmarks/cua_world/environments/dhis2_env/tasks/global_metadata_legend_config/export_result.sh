#!/bin/bash
# Export script for Global Metadata Legend Configuration

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Inline API helper if needed
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
fi

# 1. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Task Start Time
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# 3. Query the Legend Set
echo "Querying for 'RMNCH Standard Scorecard' Legend Set..."
# URL encode spaces: RMNCH%20Standard%20Scorecard
LS_RESPONSE=$(dhis2_api "legendSets?filter=name:eq:RMNCH%20Standard%20Scorecard&fields=id,name,created,legends[id,name,startValue,endValue,color]&paging=false")

# 4. Query the Indicator
echo "Querying for 'Institutional delivery rate' Indicator..."
# URL encode: Institutional%20delivery%20rate
IND_RESPONSE=$(dhis2_api "indicators?filter=name:ilike:Institutional%20delivery%20rate&fields=id,name,lastUpdated,legendSet[id,name]&paging=false")

# 5. Process and Combine Data using Python
# We pipe both JSONs into a python script to create the final result
python3 -c "
import json
import os
from datetime import datetime

# Load data
try:
    ls_data = json.loads('''$LS_RESPONSE''')
    ind_data = json.loads('''$IND_RESPONSE''')
except Exception as e:
    ls_data = {}
    ind_data = {}
    print(f'Error parsing JSON: {e}')

task_start_iso = '$TASK_START_ISO'
result = {
    'legend_set_found': False,
    'legend_set_id': None,
    'legend_items': [],
    'legend_items_count': 0,
    'indicator_found': False,
    'indicator_linked_legend_set_id': None,
    'linkage_correct': False,
    'indicator_updated_after_start': False,
    'task_start': task_start_iso
}

# Analyze Legend Set
legend_sets = ls_data.get('legendSets', [])
if legend_sets:
    ls = legend_sets[0]
    result['legend_set_found'] = True
    result['legend_set_id'] = ls.get('id')
    result['legend_items'] = ls.get('legends', [])
    result['legend_items_count'] = len(result['legend_items'])

# Analyze Indicator
indicators = ind_data.get('indicators', [])
if indicators:
    ind = indicators[0]
    result['indicator_found'] = True
    
    # Check linkage
    ls_linked = ind.get('legendSet', {})
    if ls_linked:
        result['indicator_linked_legend_set_id'] = ls_linked.get('id')
    
    # Verify linkage
    if result['legend_set_found'] and result['indicator_linked_legend_set_id'] == result['legend_set_id']:
        result['linkage_correct'] = True

    # Check timestamp (anti-gaming)
    # Convert DHIS2 ISO format to comparable
    try:
        last_updated = ind.get('lastUpdated', '')
        # Simple string comparison usually works for ISO if timezones match, 
        # but let's be loose since we just want to know if it was touched recently
        if last_updated > task_start_iso:
            result['indicator_updated_after_start'] = True
    except:
        pass

# Output to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Result processing complete.')
"

# 6. Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json