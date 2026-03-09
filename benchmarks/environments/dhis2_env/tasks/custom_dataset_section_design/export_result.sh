#!/bin/bash
# Export script for Custom Dataset Section Design task

echo "=== Exporting Custom Dataset Result ==="

source /workspace/scripts/task_utils.sh

# Fallbacks
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Fetching dataset metadata..."
# Get dataset details including sections and assigned org units
# Note: fields=sections[name,dataElements] gets section details
DS_JSON=$(dhis2_api "dataSets?filter=name:eq:Vector%20Control%20Pilot%202024&fields=id,name,periodType,organisationUnits[id,name],dataSetElements[dataElement],sections[id,name,dataElements[id]]&paging=false")

echo "Parsing dataset metadata..."
METADATA_RESULT=$(echo "$DS_JSON" | python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
    datasets = data.get('dataSets', [])
    
    if not datasets:
        print(json.dumps({'found': False}))
    else:
        ds = datasets[0]
        sections = ds.get('sections', [])
        org_units = ds.get('organisationUnits', [])
        ds_elements = ds.get('dataSetElements', [])
        
        # Check for specific section names
        sec_names = [s.get('name', '') for s in sections]
        has_prevention = any('prevention' in n.lower() for n in sec_names)
        has_case = any('case' in n.lower() and 'management' in n.lower() for n in sec_names)
        
        # Check for Bo in org units
        has_bo = any('Bo' in ou.get('name', '') for ou in org_units)
        
        print(json.dumps({
            'found': True,
            'id': ds.get('id'),
            'name': ds.get('name'),
            'periodType': ds.get('periodType'),
            'element_count': len(ds_elements),
            'section_count': len(sections),
            'section_names': sec_names,
            'has_prevention_section': has_prevention,
            'has_case_section': has_case,
            'assigned_org_unit_count': len(org_units),
            'has_bo_org_unit': has_bo
        }))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

DS_ID=$(echo "$METADATA_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id', ''))")

DATA_VALUE_FOUND="false"
if [ -n "$DS_ID" ]; then
    echo "Checking for data values entered for dataset $DS_ID..."
    # Query database for any value for this dataset in 2024 (period IDs for monthly 2024 start usually)
    # But easier to join:
    # We check if any data value exists for this dataset created/updated after task start
    
    # We verify if a value exists for period 202401 (ISO period)
    # In database, periodid needs lookup, or we use API.
    # API is safer for periods.
    
    DV_CHECK=$(dhis2_api "dataValues?dataSet=$DS_ID&period=202401&orgUnit=O6uvpzGd5pu" 2>/dev/null) # O6uvpzGd5pu is Bo
    # The agent might have chosen a facility WITHIN Bo.
    # SQL is better here to catch ANY org unit.
    
    SQL_COUNT=$(dhis2_query "
        SELECT COUNT(*) 
        FROM datavalue dv
        JOIN dataset ds ON dv.dataelementid IN (
            SELECT dataelementid FROM datasetmembers WHERE datasetid = (SELECT datasetid FROM dataset WHERE uid = '$DS_ID')
        )
        WHERE dv.lastupdated >= to_timestamp($TASK_START_EPOCH)
    " | tr -d ' ')
    
    # Alternative SQL checking specific dataset if datavalue stored link (it doesn't directly, it links via dataelement)
    # However, if they entered data for this dataset, it updated a data value for one of the elements IN the dataset.
    # To be precise, we want to know if they entered it via the form.
    # A simpler proxy: Did they enter ANY data for the elements assigned to this dataset after start?
    
    if [ "$SQL_COUNT" -gt 0 ] 2>/dev/null; then
        DATA_VALUE_FOUND="true"
    fi
fi

# Write result
cat > /tmp/custom_dataset_result.json << EOF
{
    "metadata": $METADATA_RESULT,
    "data_entry": {
        "value_entered": $DATA_VALUE_FOUND,
        "raw_sql_count": "$SQL_COUNT"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/custom_dataset_result.json"
cat /tmp/custom_dataset_result.json