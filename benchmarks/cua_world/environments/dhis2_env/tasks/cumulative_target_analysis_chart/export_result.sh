#!/bin/bash
# Export script for Cumulative Target Analysis Chart task

echo "=== Exporting Cumulative Target Analysis Chart Result ==="

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

echo "Baseline visualizations: $INITIAL_VIZ_COUNT"

# Query for the specific visualization by name
TARGET_NAME="Bo Malaria Cumulative Analysis 2023"
echo "Querying for visualization: '$TARGET_NAME'..."

# We fetch fields relevant to the task requirements:
# - cumulativeValues (bool)
# - targetLineValue, targetLineLabel
# - baseLineValue, baseLineLabel
# - dataDimensionItems (to check for malaria data)
# - organisationUnits (to check for Bo)
# - periods (to check for 2023/monthly)
VIZ_RESULT=$(dhis2_api "visualizations?filter=displayName:ilike:Bo Malaria Cumulative Analysis 2023&fields=id,displayName,created,cumulativeValues,targetLineValue,targetLineLabel,baseLineValue,baseLineLabel,dataDimensionItems[dataElement[name]],organisationUnits[name],periods[name],relativePeriods&paging=false" 2>/dev/null)

echo "Parsing visualization data..."
# Use Python to parse and validate against task requirements
VIZ_DATA=$(echo "$VIZ_RESULT" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    # Simplified ISO parsing for setup script compatibility
    try:
        from dateutil import parser
        task_start = parser.parse(task_start_iso)
    except:
        # Fallback manual parsing if dateutil not available
        task_start_iso = task_start_iso.replace('Z', '+00:00')
        if '+' not in task_start_iso: task_start_iso += '+00:00'
        task_start = datetime.fromisoformat(task_start_iso)

    visualizations = data.get('visualizations', [])
    
    # Filter for items created/modified after start? 
    # Since we deleted pre-existing ones in setup, existence is a strong signal.
    # We'll take the most recent one matching the name.
    
    found_viz = None
    if visualizations:
        # Sort by created desc
        visualizations.sort(key=lambda x: x.get('created', ''), reverse=True)
        found_viz = visualizations[0]

    if not found_viz:
        print(json.dumps({'found': False}))
        sys.exit(0)

    # Extract details
    details = {
        'found': True,
        'id': found_viz.get('id'),
        'name': found_viz.get('displayName'),
        'created': found_viz.get('created'),
        'cumulative_values': found_viz.get('cumulativeValues', False),
        'target_line_value': found_viz.get('targetLineValue'),
        'base_line_value': found_viz.get('baseLineValue'),
        
        # Check Data
        'data_elements': [
            item.get('dataElement', {}).get('name', '') 
            for item in found_viz.get('dataDimensionItems', []) 
            if item.get('dataElement')
        ],
        
        # Check Org Units
        'org_units': [ou.get('name', '') for ou in found_viz.get('organisationUnits', [])],
        
        # Check Periods
        'periods': [p.get('name', '') for p in found_viz.get('periods', [])],
        'relative_periods': found_viz.get('relativePeriods', {})
    }
    
    print(json.dumps(details))

except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"found": false}')

echo "Visualization Data Extracted:"
echo "$VIZ_DATA" | python3 -m json.tool 2>/dev/null || echo "$VIZ_DATA"

# Write result to file
cat > /tmp/task_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_viz_count": $INITIAL_VIZ_COUNT,
    "visualization_data": $VIZ_DATA,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo ""
echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="