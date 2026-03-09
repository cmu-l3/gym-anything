#!/bin/bash
# Export script for Hospital Catchment Radius Map task

echo "=== Exporting Hospital Catchment Radius Map Result ==="

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
INITIAL_MAP_COUNT=$(cat /tmp/initial_map_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Baseline map count: $INITIAL_MAP_COUNT"

# Query for maps created after task start, specifically looking for "Catchment" or "Bo"
# We fetch details including mapViews (layers) to verify configuration
echo "Querying for new maps..."
MAP_RESULT=$(dhis2_api "maps?fields=id,displayName,created,mapViews[layer,areaRadius,organisationUnits[displayName],organisationUnitGroups[displayName]]&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        # Handle simple ISO matching
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    maps = data.get('maps', [])
    candidates = []

    for m in maps:
        created_str = m.get('created', '2000-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            # Check if created after start OR if it looks like the target map (in case clock skew)
            name = m.get('displayName', '').lower()
            if created >= task_start or ('catchment' in name and 'bo' in name):
                candidates.append(m)
        except:
            pass
    
    # Sort candidates by creation time desc
    # (Simple string sort works for ISO dates usually)
    candidates.sort(key=lambda x: x.get('created', ''), reverse=True)
    
    best_match = None
    if candidates:
        best_match = candidates[0]
        # Prefer one with correct name pattern if multiple exist
        for c in candidates:
            if 'catchment' in c.get('displayName', '').lower():
                best_match = c
                break

    if best_match:
        # Analyze layers of the best match
        layers = best_match.get('mapViews', [])
        org_unit_layer = None
        for l in layers:
            # DHIS2 API layer types: 'facility', 'boundary', 'thematic'
            # Sometimes 'orgUnit' is implied by presence of organisationUnits
            if l.get('layer') in ['facility', 'orgUnit', 'boundary'] or 'organisationUnitGroups' in l:
                org_unit_layer = l
                break
        
        print(json.dumps({
            'found': True,
            'map_name': best_match.get('displayName', ''),
            'created': best_match.get('created', ''),
            'layer_found': org_unit_layer is not None,
            'layer_data': org_unit_layer if org_unit_layer else {},
            'raw_layers': layers
        }))
    else:
        print(json.dumps({'found': False}))

except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"found": false}')

# Save result to JSON
echo "$MAP_RESULT" > /tmp/hospital_catchment_result.json
chmod 666 /tmp/hospital_catchment_result.json 2>/dev/null || true

echo "Result summary:"
echo "$MAP_RESULT" | jq .found 2>/dev/null || echo "jq not found, raw: $MAP_RESULT"

echo "=== Export Complete ==="