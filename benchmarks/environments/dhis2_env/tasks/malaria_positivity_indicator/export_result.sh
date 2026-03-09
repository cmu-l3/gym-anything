#!/bin/bash
# Export script for Malaria Positivity Indicator task

echo "=== Exporting Malaria Positivity Indicator Result ==="

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
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' ' || echo "0")

# 1. Check for new Indicator
echo "Checking for new indicators..."
INDICATOR_RESULT=$(dhis2_api "indicators?fields=id,displayName,created,indicatorType[factor],numerator,denominator&paging=false&filter=displayName:ilike:malaria" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    # Simple ISO parsing fallback
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2023, 1, 1)

    found_inds = []
    for ind in data.get('indicators', []):
        created_str = ind.get('created', '2000-01-01')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            if created >= task_start:
                found_inds.append(ind)
        except:
            pass

    # Filter for positivity/RDT related
    relevant_inds = [i for i in found_inds if 'pos' in i.get('displayName','').lower() or 'rdt' in i.get('displayName','').lower()]
    
    # Get details of best match
    best_match = relevant_inds[0] if relevant_inds else {}
    
    print(json.dumps({
        'indicator_created': len(relevant_inds) > 0,
        'indicator_count': len(relevant_inds),
        'best_match': best_match
    }))
except Exception as e:
    print(json.dumps({'indicator_created': False, 'error': str(e)}))
" 2>/dev/null || echo '{"indicator_created": false}')

# 2. Check for new Visualization
echo "Checking for new visualizations..."
VIZ_RESULT=$(dhis2_api "visualizations?fields=id,displayName,created,type&paging=false&filter=displayName:ilike:malaria" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2023, 1, 1)

    found_viz = []
    for v in data.get('visualizations', []):
        created_str = v.get('created', '2000-01-01')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            if created >= task_start:
                found_viz.append(v)
        except:
            pass
            
    print(json.dumps({
        'visualization_created': len(found_viz) > 0,
        'visualization_names': [v.get('displayName') for v in found_viz]
    }))
except Exception as e:
    print(json.dumps({'visualization_created': False, 'error': str(e)}))
" 2>/dev/null || echo '{"visualization_created": false}')

# 3. Check Downloads
echo "Checking downloads..."
DOWNLOADS_RESULT=$(python3 << 'PYEOF'
import os, json
downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")

new_files = []
if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            if mtime >= task_start_epoch:
                ext = os.path.splitext(fname)[1].lower()
                if ext in ['.csv', '.xls', '.xlsx']:
                    new_files.append(fname)

print(json.dumps({
    "file_exported": len(new_files) > 0,
    "files": new_files
}))
PYEOF
)

# Combine results
cat > /tmp/malaria_positivity_indicator_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "indicator_check": $INDICATOR_RESULT,
    "visualization_check": $VIZ_RESULT,
    "download_check": $DOWNLOADS_RESULT,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/malaria_positivity_indicator_result.json 2>/dev/null || true
echo "Result exported to /tmp/malaria_positivity_indicator_result.json"
cat /tmp/malaria_positivity_indicator_result.json