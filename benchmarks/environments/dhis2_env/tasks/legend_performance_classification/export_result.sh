#!/bin/bash
# Export script for Legend Performance Classification task

echo "=== Exporting Legend Performance Classification Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying newly created Legend Sets..."

# Python script to analyze Legend Sets
LEGEND_RESULT=$(dhis2_api "legendSets?fields=id,displayName,created,legends[id,name,startValue,endValue,color]&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        # Normalize timezone handling
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    initial_ids = set()
    try:
        with open('/tmp/initial_legend_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    target_legends = []
    
    for ls in data.get('legendSets', []):
        ls_id = ls.get('id')
        
        # Check creation time OR if it's not in initial list (more robust)
        is_new = ls_id not in initial_ids
        
        created_str = ls.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            created_during_task = created >= task_start
        except:
            created_during_task = False

        name = ls.get('displayName', '')
        # Filter for relevant names
        if 'epi' in name.lower() or 'coverage' in name.lower() or 'performance' in name.lower():
            # If it's new OR created during task
            if is_new or created_during_task:
                # Analyze items
                items = ls.get('legends', [])
                colors = set(l.get('color', '').lower() for l in items if l.get('color'))
                
                min_start = min([float(l.get('startValue', 0)) for l in items]) if items else 0
                max_end = max([float(l.get('endValue', 0)) for l in items]) if items else 0
                
                target_legends.append({
                    'id': ls_id,
                    'name': name,
                    'item_count': len(items),
                    'distinct_color_count': len(colors),
                    'min_start': min_start,
                    'max_end': max_end,
                    'created_during_task': True
                })

    # Return the best match (most items) if multiple found
    target_legends.sort(key=lambda x: x['item_count'], reverse=True)
    
    print(json.dumps({
        'found': len(target_legends) > 0,
        'count': len(target_legends),
        'best_match': target_legends[0] if target_legends else None
    }))

except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"found": false}')

echo "Legend Result: $LEGEND_RESULT"

echo "Querying newly created Visualizations..."

# Python script to analyze Visualizations
VIZ_RESULT=$(dhis2_api "visualizations?fields=id,displayName,created,type,legendSet[id,displayName],legendSets[id,displayName]&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    initial_ids = set()
    try:
        with open('/tmp/initial_viz_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    target_viz = []

    for v in data.get('visualizations', []):
        v_id = v.get('id')
        is_new = v_id not in initial_ids
        
        created_str = v.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            created_during_task = created >= task_start
        except:
            created_during_task = False

        name = v.get('displayName', '')
        # Filter for relevant names
        if 'immunization' in name.lower() or 'scorecard' in name.lower() or 'district' in name.lower():
            if is_new or created_during_task:
                # Check for applied legend
                # DHIS2 API might put it in legendSet or legendSets list
                legend_applied = False
                legend_name = ''
                
                ls = v.get('legendSet')
                if ls:
                    legend_applied = True
                    legend_name = ls.get('displayName', '')
                
                lss = v.get('legendSets', [])
                if lss:
                    legend_applied = True
                    legend_name = lss[0].get('displayName', '')

                target_viz.append({
                    'id': v_id,
                    'name': name,
                    'type': v.get('type', ''),
                    'created_during_task': True,
                    'legend_applied': legend_applied,
                    'legend_applied_name': legend_name
                })

    target_viz.sort(key=lambda x: x['created_during_task'], reverse=True)

    print(json.dumps({
        'found': len(target_viz) > 0,
        'count': len(target_viz),
        'best_match': target_viz[0] if target_viz else None
    }))

except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"found": false}')

echo "Viz Result: $VIZ_RESULT"

# Combine into final result
cat > /tmp/legend_performance_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "legend_analysis": $LEGEND_RESULT,
    "viz_analysis": $VIZ_RESULT,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/legend_performance_result.json 2>/dev/null || true
echo "Result saved to /tmp/legend_performance_result.json"
cat /tmp/legend_performance_result.json

echo "=== Export Complete ==="