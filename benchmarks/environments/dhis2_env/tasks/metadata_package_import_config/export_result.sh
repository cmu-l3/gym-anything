#!/bin/bash
echo "=== Exporting Metadata Import Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Expected UIDs from the setup script
UID_1="CommHlth001"
UID_2="CommHlth002"
UID_3="CommHlth003"
EXPECTED_UIDS="$UID_1,$UID_2,$UID_3"

# --- QUERY DATA ELEMENTS ---
echo "Checking Data Elements..."
# We filter by the specific UIDs. If they exist, it implies successful import (or expert manual hacking).
# If the user created them manually via UI, they would have random UIDs and this check will fail (Anti-gaming).
DE_RESPONSE=$(dhis2_api "dataElements?filter=id:in:[$EXPECTED_UIDS]&fields=id,name,created&paging=false")

DE_COUNT=$(echo "$DE_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('dataElements', [])))" 2>/dev/null || echo "0")
echo "Found $DE_COUNT/3 expected Data Elements"

# --- QUERY DATASET ---
echo "Checking Dataset..."
# Look for dataset with matching name
DS_RESPONSE=$(dhis2_api "dataSets?filter=name:like:Community%20Health&fields=id,name,periodType,created,dataSetElements[dataElement[id]],organisationUnits[id,name]&paging=false")

# Parse Dataset details using Python for robustness
DS_DETAILS=$(echo "$DS_RESPONSE" | python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
    datasets = data.get('dataSets', [])
    
    if not datasets:
        print(json.dumps({'found': False}))
    else:
        # Pick the best match or the first one
        ds = datasets[0]
        
        # Check if expected DEs are linked
        ds_elements = ds.get('dataSetElements', [])
        linked_ids = [e['dataElement']['id'] for e in ds_elements]
        expected_ids = ['$UID_1', '$UID_2', '$UID_3']
        linked_count = sum(1 for uid in expected_ids if uid in linked_ids)
        
        # Check org unit assignment
        org_units = ds.get('organisationUnits', [])
        assigned_count = len(org_units)
        
        print(json.dumps({
            'found': True,
            'id': ds.get('id'),
            'name': ds.get('name'),
            'periodType': ds.get('periodType'),
            'linked_de_count': linked_count,
            'assigned_ou_count': assigned_count,
            'created': ds.get('created')
        }))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null)

echo "Dataset details: $DS_DETAILS"

# --- CONSTRUCT RESULT JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_iso": "$(cat /tmp/task_start_iso.txt 2>/dev/null)",
    "data_elements_found_count": $DE_COUNT,
    "dataset_check": $DS_DETAILS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="