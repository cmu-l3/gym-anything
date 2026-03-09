#!/bin/bash
# Export script for Custom Indicator Factor task

echo "=== Exporting Custom Indicator Factor Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying DHIS2 Metadata..."

# 1. Check for Indicator Type with factor 10000
echo "Checking Indicator Types..."
TYPE_RESULT=$(dhis2_api "indicatorTypes?filter=factor:eq:10000&fields=id,name,factor,created&paging=false" 2>/dev/null)

# 2. Check for Indicator
echo "Checking Indicators..."
# Search by partial name to be robust
IND_RESULT=$(dhis2_api "indicators?filter=name:ilike:OPD&fields=id,name,shortName,indicatorType[id,factor,name],numerator,denominator,created,numeratorDescription,denominatorDescription&paging=false" 2>/dev/null)

# 3. Check for Visualization
echo "Checking Visualizations..."
VIZ_RESULT=$(dhis2_api "visualizations?filter=name:ilike:OPD&fields=id,name,created,dataDimensionItems[indicator[id,name]]&paging=false" 2>/dev/null)

# Compile results using Python
echo "Compiling results..."
python3 << PYEOF > /tmp/custom_indicator_result.json
import json
import sys
from datetime import datetime

def parse_dhis_date(date_str):
    if not date_str: return datetime.min
    try:
        # Handle formats like 2023-10-25T12:00:00.000 or 2023-10-25T12:00:00.000+0000
        return datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except:
        return datetime.min

task_start_iso = "$TASK_START_ISO"

try:
    type_data = json.loads('''$TYPE_RESULT''')
    ind_data = json.loads('''$IND_RESULT''')
    viz_data = json.loads('''$VIZ_RESULT''')
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(0)

result = {
    "task_start": task_start_iso,
    "indicator_type": {"found": False},
    "indicator": {"found": False},
    "visualization": {"found": False}
}

# Analyze Indicator Type
types = type_data.get('indicatorTypes', [])
for t in types:
    if t.get('factor') == 10000:
        result['indicator_type'] = {
            "found": True,
            "id": t.get('id'),
            "name": t.get('name'),
            "factor": t.get('factor'),
            "created": t.get('created')
        }
        break

# Analyze Indicator
inds = ind_data.get('indicators', [])
target_ind = None
for i in inds:
    # Look for name match
    if "10,000" in i.get('name', '') or "10000" in i.get('name', ''):
        target_ind = i
        break

if target_ind:
    itype = target_ind.get('indicatorType', {})
    result['indicator'] = {
        "found": True,
        "id": target_ind.get('id'),
        "name": target_ind.get('name'),
        "numerator": target_ind.get('numerator', ''),
        "denominator": target_ind.get('denominator', ''),
        "type_id": itype.get('id'),
        "type_factor": itype.get('factor'),
        "created": target_ind.get('created')
    }

# Analyze Visualization
vizs = viz_data.get('visualizations', [])
target_viz = None
for v in vizs:
    if "OPD Burden Analysis" in v.get('name', ''):
        target_viz = v
        break

if target_viz:
    # Check if visualization uses the indicator
    uses_ind = False
    if target_ind:
        for item in target_viz.get('dataDimensionItems', []):
            if item.get('indicator', {}).get('id') == target_ind.get('id'):
                uses_ind = True
                break
    
    result['visualization'] = {
        "found": True,
        "id": target_viz.get('id'),
        "name": target_viz.get('name'),
        "uses_target_indicator": uses_ind,
        "created": target_viz.get('created')
    }

print(json.dumps(result, indent=2))
PYEOF

echo "Result JSON generated at /tmp/custom_indicator_result.json"
cat /tmp/custom_indicator_result.json
echo "=== Export Complete ==="