#!/bin/bash
# Export script for Malaria Burden Dashboard task

echo "=== Exporting Malaria Burden Dashboard Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Inline fallback definitions
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

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read baseline values
INITIAL_DASHBOARD_COUNT=$(cat /tmp/initial_dashboard_count 2>/dev/null | tr -d ' ' || echo "0")
INITIAL_VIZ_COUNT=$(cat /tmp/initial_visualization_count 2>/dev/null | tr -d ' ' || echo "0")
INITIAL_MAP_COUNT=$(cat /tmp/initial_map_count 2>/dev/null | tr -d ' ' || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Baseline: dashboards=$INITIAL_DASHBOARD_COUNT, visualizations=$INITIAL_VIZ_COUNT, maps=$INITIAL_MAP_COUNT"

# Query current dashboard count
echo "Querying current dashboards..."
DASHBOARD_JSON=$(dhis2_api "dashboards?fields=id,displayName,created,lastUpdated,dashboardItems~size&paging=false" 2>/dev/null)
CURRENT_DASHBOARD_COUNT=$(echo "$DASHBOARD_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(len(d.get('dashboards', [])))
except:
    print(0)
" 2>/dev/null || echo "0")

echo "Current dashboard count: $CURRENT_DASHBOARD_COUNT"

# Load initial dashboard IDs to detect truly new dashboards
INITIAL_IDS=$(cat /tmp/initial_dashboard_ids 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "Initial dashboard IDs count: $(cat /tmp/initial_dashboard_ids 2>/dev/null | wc -l)"

# Find dashboards with malaria-related names that are NEWLY created (not in initial set)
echo "Finding malaria-related dashboards..."
MALARIA_DASHBOARD_DATA=$(dhis2_api "dashboards?fields=id,displayName,created,lastUpdated&paging=false" 2>/dev/null | \
python3 -c "
import json, sys, re
from datetime import datetime, timezone

def parse_dhis2_date(s):
    if not s:
        return None
    # Handle milliseconds and various timezone formats
    s = s.replace('Z', '+00:00')
    # Handle +0000 -> +00:00
    import re as _re
    s = _re.sub(r'([+-])(\d{2})(\d{2})$', r'\1\2:\3', s)
    try:
        return datetime.fromisoformat(s)
    except:
        pass
    # Strip milliseconds and retry
    s2 = _re.sub(r'\.\d+', '', s)
    try:
        return datetime.fromisoformat(s2)
    except:
        return None

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    task_start = parse_dhis2_date(task_start_iso)
    if task_start is None:
        task_start = datetime(2020, 1, 1, tzinfo=timezone.utc)

    # Load initial IDs to detect new dashboards
    initial_ids = set()
    try:
        with open('/tmp/initial_dashboard_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    keywords = ['malaria', 'burden']
    result = {'found': False, 'name': '', 'id': '', 'created_after_start': False, 'is_new_dashboard': False}

    for dash in data.get('dashboards', []):
        name_lower = dash.get('displayName', '').lower()
        dash_id = dash.get('id', '')
        if any(k in name_lower for k in keywords):
            is_new = dash_id not in initial_ids
            created_dt = parse_dhis2_date(dash.get('created', ''))
            created_after = (created_dt is not None and task_start is not None and created_dt >= task_start) or False
            # Only report as found if it is a new dashboard (not pre-existing)
            if is_new:
                result = {
                    'found': True,
                    'name': dash.get('displayName', ''),
                    'id': dash_id,
                    'created_after_start': created_after,
                    'is_new_dashboard': True
                }
                break

    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'found': False, 'name': '', 'id': '', 'error': str(e)}))
" 2>/dev/null || echo '{"found": false}')

DASHBOARD_FOUND=$(echo "$MALARIA_DASHBOARD_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('found', False)).lower())" 2>/dev/null || echo "false")
DASHBOARD_ID=$(echo "$MALARIA_DASHBOARD_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id', ''))" 2>/dev/null || echo "")
DASHBOARD_NAME=$(echo "$MALARIA_DASHBOARD_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name', ''))" 2>/dev/null || echo "")
DASHBOARD_CREATED_AFTER=$(echo "$MALARIA_DASHBOARD_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('created_after_start', False)).lower())" 2>/dev/null || echo "false")

echo "Dashboard found: $DASHBOARD_FOUND, ID: $DASHBOARD_ID, Name: $DASHBOARD_NAME"

# Get dashboard item count if dashboard was found
DASHBOARD_ITEM_COUNT=0
if [ "$DASHBOARD_FOUND" = "true" ] && [ -n "$DASHBOARD_ID" ]; then
    ITEM_DATA=$(dhis2_api "dashboards/$DASHBOARD_ID?fields=dashboardItems" 2>/dev/null)
    DASHBOARD_ITEM_COUNT=$(echo "$ITEM_DATA" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    items = d.get('dashboardItems', [])
    print(len(items))
except:
    print(0)
" 2>/dev/null || echo "0")
fi
echo "Dashboard item count: $DASHBOARD_ITEM_COUNT"

# Query visualizations created after task start
echo "Querying recent visualizations..."
VIZ_DATA=$(dhis2_api "visualizations?fields=id,displayName,created,lastUpdated,type&paging=false&order=created:desc&pageSize=50" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    new_viz = [v for v in data.get('visualizations', [])
               if datetime.fromisoformat(v.get('created','2020-01-01T00:00:00').replace('Z','+00:00').replace('+0000','+00:00')) >= task_start]

    types = [v.get('type','') for v in new_viz]
    result = {
        'count': len(new_viz),
        'types': types,
        'has_column': any(t in ['COLUMN','BAR'] for t in types),
        'has_pivot': any(t == 'PIVOT_TABLE' for t in types),
        'has_line': any(t == 'LINE' for t in types),
        'names': [v.get('displayName','') for v in new_viz]
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"count": 0}')

NEW_VIZ_COUNT=$(echo "$VIZ_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('count', 0))" 2>/dev/null || echo "0")
HAS_COLUMN_VIZ=$(echo "$VIZ_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('has_column', False)).lower())" 2>/dev/null || echo "false")
HAS_PIVOT_VIZ=$(echo "$VIZ_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('has_pivot', False)).lower())" 2>/dev/null || echo "false")

echo "New visualizations: $NEW_VIZ_COUNT, has_column: $HAS_COLUMN_VIZ, has_pivot: $HAS_PIVOT_VIZ"

# Query maps created after task start
echo "Querying recent maps..."
MAP_DATA=$(dhis2_api "maps?fields=id,displayName,created&paging=false&order=created:desc&pageSize=20" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    new_maps = [m for m in data.get('maps', [])
                if datetime.fromisoformat(m.get('created','2020-01-01T00:00:00').replace('Z','+00:00').replace('+0000','+00:00')) >= task_start]
    print(json.dumps({'count': len(new_maps), 'names': [m.get('displayName','') for m in new_maps]}))
except Exception as e:
    print(json.dumps({'count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"count": 0}')

NEW_MAP_COUNT=$(echo "$MAP_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('count',0))" 2>/dev/null || echo "0")
echo "New maps: $NEW_MAP_COUNT"

# Write result JSON
cat > /tmp/malaria_burden_dashboard_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_dashboard_count": $INITIAL_DASHBOARD_COUNT,
    "current_dashboard_count": $CURRENT_DASHBOARD_COUNT,
    "dashboard_found": $DASHBOARD_FOUND,
    "dashboard_id": "$DASHBOARD_ID",
    "dashboard_name": "$DASHBOARD_NAME",
    "dashboard_created_after_start": $DASHBOARD_CREATED_AFTER,
    "dashboard_item_count": $DASHBOARD_ITEM_COUNT,
    "new_visualization_count": $NEW_VIZ_COUNT,
    "new_map_count": $NEW_MAP_COUNT,
    "has_column_or_bar_chart": $HAS_COLUMN_VIZ,
    "has_pivot_table": $HAS_PIVOT_VIZ,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/malaria_burden_dashboard_result.json 2>/dev/null || true
echo ""
echo "Result JSON saved to /tmp/malaria_burden_dashboard_result.json"
cat /tmp/malaria_burden_dashboard_result.json
echo ""
echo "=== Export Complete ==="
