#!/bin/bash
# Export script for Dataset Governance Config task

echo "=== Exporting Dataset Governance Config Result ==="

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

echo "Querying Malaria datasets..."

# We fetch datasets containing 'Malaria' in the name.
# We need fields: id, displayName, timelyDays, expiryDays, compulsoryDataElements[id,displayName]
# We also want lastUpdated to check against task start time.
DATASET_RESULT=$(dhis2_api "dataSets?filter=name:ilike:Malaria&fields=id,displayName,timelyDays,expiryDays,lastUpdated,compulsoryDataElements[id,displayName]&paging=false" 2>/dev/null)

echo "API Response received."

# Parse with Python to create a clean JSON result
RESULT_JSON=$(echo "$DATASET_RESULT" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    datasets = data.get('dataSets', [])
    
    task_start_iso = '$TASK_START_ISO'
    # Simple ISO parse for comparison
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    processed_datasets = []
    
    for ds in datasets:
        # Check lastUpdated
        updated_str = ds.get('lastUpdated', '2020-01-01T00:00:00')
        try:
            updated = datetime.fromisoformat(updated_str.replace('Z','+00:00').replace('+0000','+00:00'))
            modified_during_task = updated >= task_start
        except:
            modified_during_task = False

        compulsory = [el.get('displayName', '') for el in ds.get('compulsoryDataElements', [])]
        
        processed_datasets.append({
            'id': ds.get('id'),
            'displayName': ds.get('displayName'),
            'timelyDays': ds.get('timelyDays'),
            'expiryDays': ds.get('expiryDays'),
            'compulsoryDataElements': compulsory,
            'modified_during_task': modified_during_task
        })

    print(json.dumps({
        'datasets': processed_datasets,
        'count': len(processed_datasets)
    }))

except Exception as e:
    print(json.dumps({'datasets': [], 'count': 0, 'error': str(e)}))
" 2>/dev/null)

# Save result to file
cat > /tmp/dataset_governance_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "api_result": $RESULT_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/dataset_governance_result.json 2>/dev/null || true

echo "Result saved to /tmp/dataset_governance_result.json"
cat /tmp/dataset_governance_result.json
echo ""
echo "=== Export Complete ==="