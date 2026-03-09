#!/bin/bash
# Export script for Org Unit Redistricting task

echo "=== Exporting Org Unit Redistricting Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        curl -s -u admin:district "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Collecting validation data via API..."

# 1. Look for 'Tikonko North'
echo "Searching for Tikonko North..."
NEW_UNIT_DATA=$(dhis2_api "organisationUnits?filter=name:eq:Tikonko%20North&fields=id,name,shortName,openingDate,parent[id,name,level]&paging=false" 2>/dev/null)

# 2. Look for the facilities to check their parents
echo "Checking facilities status..."
TIKONKO_CHC_DATA=$(dhis2_api "organisationUnits?filter=name:eq:Tikonko%20CHC&fields=id,name,parent[id,name]&paging=false" 2>/dev/null)
GONDAMA_MCHP_DATA=$(dhis2_api "organisationUnits?filter=name:eq:Gondama%20MCHP&fields=id,name,parent[id,name]&paging=false" 2>/dev/null)

# 3. Look for 'Bo' to confirm parentage ID
BO_DATA=$(dhis2_api "organisationUnits?filter=name:eq:Bo&fields=id,name&paging=false" 2>/dev/null)

# Create a Python script to parse and combine this data into a clean JSON
cat > /tmp/process_results.py << 'PYEOF'
import json
import sys
import os

def load_json_arg(arg_index):
    try:
        if arg_index < len(sys.argv):
            return json.loads(sys.argv[arg_index])
    except:
        pass
    return {}

new_unit_raw = load_json_arg(1)
chc_raw = load_json_arg(2)
mchp_raw = load_json_arg(3)
bo_raw = load_json_arg(4)
start_time = sys.argv[5]

# Process 'Tikonko North'
new_units = new_unit_raw.get('organisationUnits', [])
new_unit = new_units[0] if new_units else None

result = {
    "new_unit_found": False,
    "new_unit_props": {},
    "tikonko_chc_parent": None,
    "gondama_mchp_parent": None,
    "bo_id": None,
    "timestamp": start_time
}

if bo_raw.get('organisationUnits'):
    result['bo_id'] = bo_raw['organisationUnits'][0]['id']

if new_unit:
    result['new_unit_found'] = True
    result['new_unit_props'] = {
        "id": new_unit.get('id'),
        "name": new_unit.get('name'),
        "shortName": new_unit.get('shortName'),
        "openingDate": new_unit.get('openingDate'),
        "parent_id": new_unit.get('parent', {}).get('id'),
        "parent_name": new_unit.get('parent', {}).get('name')
    }

if chc_raw.get('organisationUnits'):
    chc = chc_raw['organisationUnits'][0]
    result['tikonko_chc_parent'] = {
        "id": chc.get('parent', {}).get('id'),
        "name": chc.get('parent', {}).get('name')
    }

if mchp_raw.get('organisationUnits'):
    mchp = mchp_raw['organisationUnits'][0]
    result['gondama_mchp_parent'] = {
        "id": mchp.get('parent', {}).get('id'),
        "name": mchp.get('parent', {}).get('name')
    }

print(json.dumps(result, indent=2))
PYEOF

python3 /tmp/process_results.py "$NEW_UNIT_DATA" "$TIKONKO_CHC_DATA" "$GONDAMA_MCHP_DATA" "$BO_DATA" "$TASK_START_EPOCH" > /tmp/org_unit_redistricting_result.json

echo "Result JSON generated:"
cat /tmp/org_unit_redistricting_result.json

# Copy to final location for verifier
chmod 666 /tmp/org_unit_redistricting_result.json 2>/dev/null || true

echo "=== Export Complete ==="