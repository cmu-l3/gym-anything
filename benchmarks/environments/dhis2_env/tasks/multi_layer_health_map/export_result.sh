#!/bin/bash
# Export script for Multi-Layer Health Map task

echo "=== Exporting Multi-Layer Health Map Result ==="

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

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' ' || echo "0")
INITIAL_MAP_COUNT=$(cat /tmp/initial_map_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Checking for new maps created after $TASK_START_ISO"

# Query DHIS2 Maps API
# We need detailed fields: mapViews (layers) and their configuration
MAPS_JSON=$(dhis2_api "maps?fields=id,displayName,created,mapViews[id,layer,columns[dimension,items[id,name]],rows[dimension,items[id,name]]]&paging=false&order=created:desc" 2>/dev/null)

# Parse API result using Python
# This script identifies if a valid map was created during the task
MAP_ANALYSIS=$(echo "$MAPS_JSON" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    # Flexible date parsing
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    maps = data.get('maps', [])
    valid_map = None
    
    # Filter for maps created during task
    new_maps = []
    for m in maps:
        created_str = m.get('created', '')
        try:
            # DHIS2 often returns ISO without colon in offset or with Z
            created_str = created_str.replace('Z', '+00:00')
            if created_str.endswith('+0000'):
                created_str = created_str[:-2] + ':' + created_str[-2:]
            
            created = datetime.fromisoformat(created_str)
            if created >= task_start:
                new_maps.append(m)
        except Exception as e:
            # If parsing fails, skip strictly or include if very recent? 
            # Safest to skip if we can't verify time.
            pass

    # Analyze the best candidate map
    best_candidate = {}
    
    # Look for map matching keywords
    keywords = ['penta', 'immunization', 'coverage', 'epi', 'facility', 'sierra']
    
    for m in new_maps:
        name = m.get('displayName', '').lower()
        map_views = m.get('mapViews', [])
        
        # Calculate score for this map to pick the best one
        score = 0
        if any(k in name for k in keywords): score += 2
        if len(map_views) >= 2: score += 3
        
        # Check layers
        has_thematic = False
        has_imm_data = False
        
        for view in map_views:
            layer_type = view.get('layer', '')
            if layer_type == 'THEMATIC1' or layer_type == 'THEMATIC2' or layer_type == 'thematic':
                has_thematic = True
            
            # Check data dimensions (columns usually holds data items)
            dims = view.get('columns', []) + view.get('rows', [])
            for dim in dims:
                for item in dim.get('items', []):
                    item_name = item.get('name', '').lower()
                    if any(x in item_name for x in ['penta', 'dpt', 'vaccine', 'dose', 'measles', 'bcg']):
                        has_imm_data = True
        
        if has_thematic: score += 1
        if has_imm_data: score += 1
        
        m['analysis_score'] = score
        m['has_thematic'] = has_thematic
        m['has_imm_data'] = has_imm_data
        m['layer_count'] = len(map_views)

    # Sort by score descending
    new_maps.sort(key=lambda x: x.get('analysis_score', 0), reverse=True)
    
    result = {
        'map_found': False,
        'map_name': '',
        'layer_count': 0,
        'has_thematic': False,
        'has_imm_data': False,
        'total_new_maps': len(new_maps)
    }
    
    if new_maps:
        best = new_maps[0]
        result['map_found'] = True
        result['map_name'] = best.get('displayName', '')
        result['layer_count'] = best.get('layer_count', 0)
        result['has_thematic'] = best.get('has_thematic', False)
        result['has_imm_data'] = best.get('has_imm_data', False)
        
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e), 'map_found': False}))
" 2>/dev/null)

echo "Map Analysis: $MAP_ANALYSIS"

# Check Downloads for image files
echo "Checking Downloads..."
DOWNLOADS_ANALYSIS=$(python3 << 'PYEOF'
import os, json

downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")

found = False
filename = ""

if os.path.exists(downloads_dir):
    # Sort by modification time, newest first
    files = []
    for f in os.listdir(downloads_dir):
        fp = os.path.join(downloads_dir, f)
        if os.path.isfile(fp):
            files.append((f, os.path.getmtime(fp)))
    
    files.sort(key=lambda x: x[1], reverse=True)
    
    for f, mtime in files:
        if mtime >= task_start_epoch:
            ext = os.path.splitext(f)[1].lower()
            if ext in ['.png', '.jpg', '.jpeg', '.pdf']:
                found = True
                filename = f
                break

print(json.dumps({
    "download_found": found,
    "filename": filename
}))
PYEOF
)

echo "Downloads Analysis: $DOWNLOADS_ANALYSIS"

# Combine into final result
cat > /tmp/task_result.json << EOF
{
    "map_analysis": $MAP_ANALYSIS,
    "download_analysis": $DOWNLOADS_ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="