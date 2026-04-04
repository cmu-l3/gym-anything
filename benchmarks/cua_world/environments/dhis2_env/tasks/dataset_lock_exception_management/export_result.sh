#!/bin/bash
# Export script for Dataset Lock Exception Management

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Helper for API calls
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district -X "${2:-GET}" \
            -H "Content-Type: application/json" \
            "http://localhost:8080/api/$1"
    }
fi

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Task Start Time
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00")

# 3. Verify Dataset Expiry Configuration
echo "Checking Dataset Configuration..."
DATASET_JSON=$(dhis2_api "dataSets?filter=name:eq:Child%20Health&fields=id,name,expiryDays,lastUpdated")

# 4. Verify Lock Exception Existence
echo "Checking Lock Exceptions..."
# We filter by period 202301 (Jan 2023) to narrow down results
LOCK_JSON=$(dhis2_api "lockExceptions?filter=period:eq:202301&fields=period,created,dataSet[id,name],organisationUnit[id,name]")

# 5. Process Data with Python to generate result JSON
python3 -c "
import json
import sys
from datetime import datetime

try:
    task_start_iso = '$TASK_START_ISO'
    
    # Parse Dataset Info
    ds_data = json.loads('''$DATASET_JSON''')
    dataset = ds_data.get('dataSets', [{}])[0]
    
    expiry_days = dataset.get('expiryDays', 0)
    ds_last_updated = dataset.get('lastUpdated', '')
    
    # Parse Lock Exception Info
    le_data = json.loads('''$LOCK_JSON''')
    exceptions = le_data.get('lockExceptions', [])
    
    found_exception = False
    exception_details = {}
    
    for ex in exceptions:
        ou_name = ex.get('organisationUnit', {}).get('name', '')
        ds_name = ex.get('dataSet', {}).get('name', '')
        
        # Check if this exception matches our target
        if 'Ngelehun' in ou_name and 'Child Health' in ds_name:
            found_exception = True
            exception_details = {
                'period': ex.get('period'),
                'created': ex.get('created'),
                'org_unit': ou_name,
                'dataset': ds_name
            }
            break
            
    result = {
        'task_start_iso': task_start_iso,
        'dataset_config': {
            'name': dataset.get('name'),
            'expiry_days': expiry_days,
            'last_updated': ds_last_updated
        },
        'lock_exception': {
            'found': found_exception,
            'details': exception_details
        },
        'timestamp': datetime.now().isoformat()
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/dataset_lock_exception_result.json

# 6. Secure the output file
chmod 666 /tmp/dataset_lock_exception_result.json 2>/dev/null || true

echo "Result exported to /tmp/dataset_lock_exception_result.json"
cat /tmp/dataset_lock_exception_result.json
echo "=== Export Complete ==="