#!/bin/bash
# Export script for Interpretation Data Review task

echo "=== Exporting Interpretation Data Review Result ==="

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
INITIAL_COUNT=$(cat /tmp/initial_interpretation_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Baseline interpretations: $INITIAL_COUNT"

# Fetch recent interpretations
# We fetch a reasonable number (e.g., 50) and filter in Python to ensure we catch everything
echo "Querying recent interpretations..."

# Interpretation object structure in API:
# { "id": "...", "created": "...", "text": "...", "visualization": { "id": "..." }, "map": { "id": "..." }, ... }
API_RESPONSE=$(dhis2_api "interpretations?fields=id,created,text,visualization[id],map[id],eventVisualization[id],eventReport[id],eventChart[id]&order=created:desc&pageSize=50" 2>/dev/null)

# Process with Python to filter by timestamp and extract metrics
INTERP_RESULT=$(echo "$API_RESPONSE" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    
    # normalize function for DHIS2 timestamps
    def parse_dt(s):
        if not s: return None
        # Handle 2023-10-27T10:00:00.123Z and +0000 formats
        s = s.replace('Z', '+00:00')
        # Simple fix for +0000 -> +00:00 if needed for fromisoformat in older pythons
        if s.endswith('+0000'): s = s[:-5] + '+00:00'
        try:
            return datetime.fromisoformat(s)
        except:
            return None

    task_start = parse_dt(task_start_iso)
    if task_start is None:
        # Fallback if timestamp file is corrupt
        task_start = datetime(2025, 1, 1)

    new_interps = []
    
    for i in data.get('interpretations', []):
        created_str = i.get('created', '')
        created_dt = parse_dt(created_str)
        
        if created_dt and created_dt >= task_start:
            # Determine visualization ID attached to this interpretation
            viz_id = None
            viz_type = 'unknown'
            
            if i.get('visualization'):
                viz_id = i['visualization'].get('id')
                viz_type = 'visualization'
            elif i.get('map'):
                viz_id = i['map'].get('id')
                viz_type = 'map'
            elif i.get('eventVisualization'):
                viz_id = i['eventVisualization'].get('id')
                viz_type = 'eventVisualization'
            elif i.get('eventReport'):
                viz_id = i['eventReport'].get('id')
                viz_type = 'eventReport'
            elif i.get('eventChart'):
                viz_id = i['eventChart'].get('id')
                viz_type = 'eventChart'

            new_interps.append({
                'id': i.get('id'),
                'text': i.get('text', ''),
                'created': created_str,
                'viz_id': viz_id,
                'viz_type': viz_type,
                'length': len(i.get('text', ''))
            })

    print(json.dumps({
        'count': len(new_interps),
        'interpretations': new_interps
    }))

except Exception as e:
    print(json.dumps({'count': 0, 'interpretations': [], 'error': str(e)}))
" 2>/dev/null || echo '{"count": 0, "interpretations": []}')

echo "Found $(echo "$INTERP_RESULT" | jq .count 2>/dev/null) new interpretations."

# Save result to JSON
cat > /tmp/interpretation_review_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_count": $INITIAL_COUNT,
    "result_data": $INTERP_RESULT,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/interpretation_review_result.json 2>/dev/null || true

echo "Result saved to /tmp/interpretation_review_result.json"
cat /tmp/interpretation_review_result.json
echo ""
echo "=== Export Complete ==="