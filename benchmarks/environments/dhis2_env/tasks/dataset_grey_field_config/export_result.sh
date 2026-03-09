#!/bin/bash
# Export script for Dataset Grey Field Configuration task

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# 1. Fetch the target Data Element
echo "Fetching Data Element..."
DE_JSON=$(dhis2_api "dataElements?filter=name:eq:Prostate+Screening+%5BTask%5D&fields=id,displayName,created,valueType,aggregationType,categoryCombo[id,name,categoryOptionCombos[id,name]]&paging=false" 2>/dev/null)

# 2. Fetch the target Dataset
echo "Fetching Dataset..."
DS_JSON=$(dhis2_api "dataSets?filter=name:ilike:PHU+Monthly+1&fields=id,displayName,dataSetElements[dataElement[id]]&paging=false" 2>/dev/null)

# 3. Fetch the target Section (if it exists)
echo "Fetching Section..."
# We need the dataset ID first to be precise, but name filter is usually enough for the task
SECTION_JSON=$(dhis2_api "sections?filter=name:eq:NCD+Screening+%5BTask%5D&fields=id,displayName,created,dataSet[id],greyedFields[dataElement[id],categoryOptionCombo[id]]&paging=false" 2>/dev/null)

# 4. Fetch Gender Category Combo details (to map Option Names to IDs)
# We need this to verify if the greyed out ID corresponds to "Female"
# The DE uses the Gender cat combo, so we can get IDs from there, but fetching specifically helps
CAT_COMBO_JSON=$(dhis2_api "categoryCombos?filter=name:eq:Gender&fields=id,name,categoryOptionCombos[id,name]&paging=false" 2>/dev/null)

# Combine into one result file using Python
python3 -c "
import json, sys

try:
    task_start = '$TASK_START_ISO'
    
    de_response = json.loads('''$DE_JSON''')
    ds_response = json.loads('''$DS_JSON''')
    section_response = json.loads('''$SECTION_JSON''')
    cc_response = json.loads('''$CAT_COMBO_JSON''')

    result = {
        'task_start': task_start,
        'data_element': None,
        'dataset': None,
        'section': None,
        'gender_options': {}
    }

    # Process Data Element
    if de_response.get('dataElements'):
        result['data_element'] = de_response['dataElements'][0]

    # Process Dataset
    if ds_response.get('dataSets'):
        # Find the specific one if multiple match (unlikely with specific name)
        ds = ds_response['dataSets'][0] 
        result['dataset'] = {
            'id': ds['id'],
            'displayName': ds['displayName'],
            'element_ids': [e['dataElement']['id'] for e in ds.get('dataSetElements', [])]
        }

    # Process Section
    if section_response.get('sections'):
        result['section'] = section_response['sections'][0]

    # Process Category Combo to map Names -> IDs
    if cc_response.get('categoryCombos'):
        cc = cc_response['categoryCombos'][0]
        # Map ID to Name and Name to ID
        result['gender_options'] = {c['id']: c['name'] for c in cc.get('categoryOptionCombos', [])}

    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/dataset_grey_field_config_result.json

echo "Result JSON saved to /tmp/dataset_grey_field_config_result.json"
cat /tmp/dataset_grey_field_config_result.json

echo "=== Export Complete ==="