#!/bin/bash
# Export script for Option Set Referral Tracking task

echo "=== Exporting Option Set Referral Tracking Result ==="

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

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Fetch created objects
echo "Fetching Option Set data..."
# Filter by name "Referral Reason"
OS_DATA=$(dhis2_api "optionSets?filter=displayName:ilike:Referral%20Reason&fields=id,displayName,code,created,valueType,options[id,displayName,code,sortOrder]&paging=false" 2>/dev/null)

echo "Fetching Data Element data..."
# Filter by name "Facility Referral Reason"
DE_DATA=$(dhis2_api "dataElements?filter=displayName:ilike:Facility%20Referral%20Reason&fields=id,displayName,code,shortName,created,domainType,valueType,optionSet[id,displayName]&paging=false" 2>/dev/null)

# 3. Get Task Start Time
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# 4. Construct Result JSON
# We use Python to parse the DHIS2 responses and format a clean result file
python3 << PYEOF
import json
import sys
from datetime import datetime

def parse_iso(s):
    try:
        # DHIS2 often returns "2023-10-27T10:00:00.123" (no Z) or with Z
        # We'll just parse broadly
        if not s: return datetime.min
        s = s.replace('Z', '')
        # Truncate fractional seconds for simpler comparison if needed, or use isoformat
        return datetime.fromisoformat(s)
    except:
        return datetime.min

try:
    task_start_str = "$TASK_START_ISO"
    task_start = parse_iso(task_start_str)

    # Parse Option Set Data
    os_resp = json.loads('''$OS_DATA''' or '{}')
    os_list = os_resp.get('optionSets', [])
    
    # Select the most likely candidate (created after task start, or just the best match)
    best_os = None
    for os_item in os_list:
        created = parse_iso(os_item.get('created'))
        # Prefer newly created ones
        if created >= task_start:
            best_os = os_item
            break
    
    if not best_os and os_list:
        best_os = os_list[0] # Fallback

    # Parse Data Element Data
    de_resp = json.loads('''$DE_DATA''' or '{}')
    de_list = de_resp.get('dataElements', [])
    
    best_de = None
    for de_item in de_list:
        created = parse_iso(de_item.get('created'))
        if created >= task_start:
            best_de = de_item
            break
            
    if not best_de and de_list:
        best_de = de_list[0]

    result = {
        "task_start_iso": task_start_str,
        "option_set": {
            "found": bool(best_os),
            "id": best_os.get('id') if best_os else None,
            "name": best_os.get('displayName') if best_os else None,
            "code": best_os.get('code') if best_os else None,
            "created": best_os.get('created') if best_os else None,
            "options": best_os.get('options', []) if best_os else []
        },
        "data_element": {
            "found": bool(best_de),
            "id": best_de.get('id') if best_de else None,
            "name": best_de.get('displayName') if best_de else None,
            "code": best_de.get('code') if best_de else None,
            "value_type": best_de.get('valueType') if best_de else None,
            "domain_type": best_de.get('domainType') if best_de else None,
            "created": best_de.get('created') if best_de else None,
            "linked_option_set_id": best_de.get('optionSet', {}).get('id') if best_de and best_de.get('optionSet') else None
        }
    }

    with open("/tmp/option_set_task_result.json", "w") as f:
        json.dump(result, f, indent=2)

except Exception as e:
    # Fallback error JSON
    with open("/tmp/option_set_task_result.json", "w") as f:
        json.dump({"error": str(e)}, f)

PYEOF

chmod 666 /tmp/option_set_task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/option_set_task_result.json
echo "=== Export Complete ==="