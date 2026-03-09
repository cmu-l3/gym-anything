#!/bin/bash
# Export script for Measles Performance Gauge Chart task

echo "=== Exporting Measles Gauge Result ==="

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
INITIAL_VIZ_COUNT=$(cat /tmp/initial_visualization_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Searching for new Gauge charts created after $TASK_START_ISO..."

# Query visualizations
# We ask for detailed fields including axes, targetLine, etc. to verify configuration
VIZ_RESULT=$(dhis2_api "visualizations?fields=id,displayName,created,type,axes,targetLineValue,baseLineValue,rangeAxisMaxValue,rangeAxisMinValue,indicators[displayName],organisationUnits[displayName]&paging=false&order=created:desc&pageSize=50" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        # Normalize date string for parsing
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    new_viz = []
    target_viz = None

    for v in data.get('visualizations', []):
        created_str = v.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            if created >= task_start:
                new_viz.append(v)
        except:
            pass

    # Find the specific target chart
    # Criteria: Gauge type + 'Measles' in name
    for v in new_viz:
        name = v.get('displayName', '').lower()
        v_type = v.get('type', '').upper()
        if 'measles' in name and v_type == 'GAUGE':
            target_viz = v
            break
            
    # If no specific Measles Gauge found, fall back to any Gauge found
    if not target_viz:
        for v in new_viz:
            if v.get('type', '').upper() == 'GAUGE':
                target_viz = v
                break

    print(json.dumps({
        'new_count': len(new_viz),
        'target_found': target_viz is not None,
        'viz_data': target_viz if target_viz else {}
    }))
except Exception as e:
    print(json.dumps({'new_count': 0, 'target_found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"new_count": 0, "target_found": false}')

# Save result to JSON
echo "$VIZ_RESULT" > /tmp/measles_gauge_result.json
chmod 666 /tmp/measles_gauge_result.json

echo "Export complete. Found target: $(echo $VIZ_RESULT | grep -o '"target_found": [a-z]*')"
cat /tmp/measles_gauge_result.json