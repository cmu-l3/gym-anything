#!/bin/bash
# Export script for Outbreak Response Dataset task

echo "=== Exporting Outbreak Response Dataset Result ==="

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

echo "Searching for created Data Sets..."

# Query API for Data Sets created/modified matching criteria
# We filter by name 'Cholera' as requested in task
# Fields needed: basic info, periodType, data elements assigned, org units assigned
API_RESPONSE=$(dhis2_api "dataSets?filter=name:ilike:Cholera&fields=id,name,shortName,periodType,created,dataSetElements[dataElement[id,name]],organisationUnits[id,name]&paging=false" 2>/dev/null)

# Parse response with Python to handle date comparison and complex validation
PYTHON_PARSER=$(cat << 'EOF'
import json
import sys
from datetime import datetime

try:
    # Read stdin
    raw_data = sys.stdin.read()
    if not raw_data:
        print(json.dumps({"error": "Empty API response"}))
        sys.exit(0)
        
    data = json.load(sys.stdin) if raw_data.strip() else {}
    if isinstance(data, str):
        data = json.loads(raw_data)
        
    task_start_iso = sys.argv[1]
    # Simple ISO parse (handle Z)
    try:
        task_start_dt = datetime.fromisoformat(task_start_iso.replace('Z', '+00:00'))
    except:
        # Fallback if isoformat fails (e.g. python < 3.7 or weird format)
        task_start_dt = datetime(2023, 1, 1)

    datasets = data.get('dataSets', [])
    
    # Find the best candidate created after task start
    candidate = None
    
    for ds in datasets:
        created_str = ds.get('created', '')
        # DHIS2 dates are usually ISO
        try:
            created_dt = datetime.fromisoformat(created_str.replace('Z', '+00:00'))
        except:
            continue
            
        # Check if created after task start
        # Allow a small buffer (e.g. 1 min before) just in case of clock skew, 
        # but primarily we want new items.
        if created_dt >= task_start_dt:
            candidate = ds
            break
            
    if not candidate and datasets:
        # If no timestamp match (maybe created time isn't updating?), take the last one
        # but mark as potentially old
        candidate = datasets[-1]
        candidate['warning'] = 'Timestamp check inconclusive'

    if candidate:
        # Extract data elements
        ds_elements = candidate.get('dataSetElements', [])
        element_names = [e.get('dataElement', {}).get('name', '') for e in ds_elements]
        
        # Extract org units
        org_units = candidate.get('organisationUnits', [])
        ou_names = [o.get('name', '') for o in org_units]
        
        result = {
            "found": True,
            "id": candidate.get('id'),
            "name": candidate.get('name'),
            "shortName": candidate.get('shortName'),
            "periodType": candidate.get('periodType'),
            "created": candidate.get('created'),
            "data_element_count": len(element_names),
            "data_element_names": element_names,
            "org_unit_count": len(ou_names),
            "org_unit_names": ou_names
        }
    else:
        result = {
            "found": False,
            "reason": "No matching data set found created after task start"
        }
        
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))
EOF
)

# Pipe API response to python script
echo "$API_RESPONSE" | python3 -c "$PYTHON_PARSER" "$TASK_START_ISO" > /tmp/outbreak_response_dataset_result.json

echo "Export complete. Result:"
cat /tmp/outbreak_response_dataset_result.json