#!/bin/bash
# Export script for Waste Management Task
# Queries DHIS2 API to verify metadata creation and data entry

echo "=== Exporting Waste Management Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district -X "${2:-GET}" "http://localhost:8080/api/$1"
    }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2024-01-01T00:00:00+0000")

# 1. Find the Target Org Unit ID (Bo Government Hospital)
echo "Looking up Org Unit..."
OU_SEARCH=$(dhis2_api "organisationUnits?filter=name:ilike:Bo%20Government%20Hospital&fields=id,name" 2>/dev/null)
OU_ID=$(echo "$OU_SEARCH" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['organisationUnits'][0]['id'] if d.get('organisationUnits') else '')" 2>/dev/null)
echo "Found Org Unit: $OU_ID"

# 2. Find Created Data Elements
echo "Looking up Data Elements..."
# Search for elements containing "Waste"
DE_SEARCH=$(dhis2_api "dataElements?filter=name:ilike:Waste&fields=id,name,shortName,valueType,aggregationType,domainType,created&paging=false" 2>/dev/null)

# 3. Find Created Dataset
echo "Looking up Dataset..."
DS_SEARCH=$(dhis2_api "dataSets?filter=name:ilike:Hospital%20Waste&fields=id,name,periodType,created,dataSetElements[dataElement[id]],organisationUnits[id]&paging=false" 2>/dev/null)

# 4. Check Data Values (if we have OU and Data Elements)
DATA_VALUES="{}"
COMPLETION_STATUS="false"

if [ -n "$OU_ID" ]; then
    # Extract DE IDs from the search result to query data
    DE_IDS=$(echo "$DE_SEARCH" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ids = [de['id'] for de in d.get('dataElements', [])]
    print(','.join(ids))
except:
    print('')
")
    
    # Also get Dataset ID
    DS_ID=$(echo "$DS_SEARCH" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataSets'][0]['id'] if d.get('dataSets') else '')" 2>/dev/null)

    if [ -n "$DE_IDS" ]; then
        echo "Querying Data Values for DEs: $DE_IDS at OU: $OU_ID"
        DATA_VALUES=$(dhis2_api "dataValues?ou=$OU_ID&pe=202401&de=$DE_IDS" 2>/dev/null)
    fi

    if [ -n "$DS_ID" ]; then
        echo "Checking dataset completion..."
        # Note: completeDataSetRegistrations endpoint
        COMP_CHECK=$(dhis2_api "completeDataSetRegistrations?dataSet=$DS_ID&period=202401&orgUnit=$OU_ID" 2>/dev/null)
        COMPLETION_STATUS=$(echo "$COMP_CHECK" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('completeDataSetRegistrations') else 'false')")
    fi
fi

# Combine all data into a Python script to structure the JSON output
python3 -c "
import json, sys, os
from datetime import datetime

task_start_iso = '$TASK_START_ISO'
ou_id = '$OU_ID'

try:
    de_data = json.loads('''$DE_SEARCH''')
    ds_data = json.loads('''$DS_SEARCH''')
    dv_raw = '''$DATA_VALUES'''
    dv_data = json.loads(dv_raw) if dv_raw and '{' in dv_raw else {}
    completion = '$COMPLETION_STATUS' == 'true'
except Exception as e:
    print(f'Error parsing API responses: {e}', file=sys.stderr)
    de_data = {}
    ds_data = {}
    dv_data = {}
    completion = False

# Helper to check timestamps
def is_new(created_str):
    if not created_str: return False
    # Simple string comparison usually works for ISO if same format, but strict parsing is safer
    # DHIS2: 2023-10-27T10:00:00.123
    return created_str >= task_start_iso

# Analyze Data Elements
created_des = []
target_gen_id = None
target_inc_id = None

for de in de_data.get('dataElements', []):
    if is_new(de.get('created')):
        name = de.get('name', '')
        info = {
            'id': de['id'],
            'name': name,
            'shortName': de.get('shortName'),
            'valueType': de.get('valueType'),
            'aggregationType': de.get('aggregationType'),
            'domainType': de.get('domainType')
        }
        created_des.append(info)
        if 'Generated' in name: target_gen_id = de['id']
        if 'Incinerated' in name: target_inc_id = de['id']

# Analyze Dataset
created_ds = []
target_ds = None

for ds in ds_data.get('dataSets', []):
    if is_new(ds.get('created')):
        # Check linkages
        ds_elements = [x['dataElement']['id'] for x in ds.get('dataSetElements', [])]
        ds_ous = [x['id'] for x in ds.get('organisationUnits', [])]
        
        info = {
            'id': ds['id'],
            'name': ds.get('name'),
            'periodType': ds.get('periodType'),
            'element_count': len(ds_elements),
            'contains_gen': target_gen_id in ds_elements if target_gen_id else False,
            'contains_inc': target_inc_id in ds_elements if target_inc_id else False,
            'assigned_to_target_ou': ou_id in ds_ous if ou_id else False
        }
        created_ds.append(info)
        if 'Hospital Waste' in ds.get('name', ''):
            target_ds = info

# Analyze Values
values_found = []
for dv in dv_data:
    # dataValues endpoint returns a list directly or inside a key? 
    # Usually just a list of objects if implicit, but API returns { dataValues: [...] }
    # Let's handle the list if it's inside 'dataValues' key
    pass 

# Correct handling of dataValues response
actual_values = dv_data if isinstance(dv_data, list) else dv_data.get('dataValues', [])
for val in actual_values:
    values_found.append({
        'de': val.get('dataElement'),
        'value': val.get('value')
    })

result = {
    'task_start': task_start_iso,
    'org_unit_found': bool(ou_id),
    'created_data_elements': created_des,
    'created_datasets': created_ds,
    'data_values': values_found,
    'dataset_complete': completion,
    'target_ids': {
        'gen': target_gen_id,
        'inc': target_inc_id
    }
}

print(json.dumps(result, indent=2))
" > /tmp/waste_management_result.json

echo "Result JSON generated at /tmp/waste_management_result.json"
cat /tmp/waste_management_result.json
echo "=== Export Complete ==="