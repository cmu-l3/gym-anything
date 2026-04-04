#!/bin/bash
# Export script for Constant Indicator Projection task

echo "=== Exporting Constant Indicator Projection Result ==="

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

echo "Querying metadata..."

# 1. Check for Constants
# We filter by name "ITN" or "Universal"
CONSTANTS_JSON=$(dhis2_api "constants?filter=name:ilike:ITN&fields=id,name,value,created&paging=false" 2>/dev/null)

# 2. Check for Indicators
# We need the numerator and denominator to verify the formula
INDICATORS_JSON=$(dhis2_api "indicators?filter=name:ilike:ITN&fields=id,name,numerator,denominator,created,indicatorType&paging=false" 2>/dev/null)

# 3. Check for Visualizations
VISUALIZATIONS_JSON=$(dhis2_api "visualizations?filter=name:ilike:ITN&fields=id,name,created,dataDimensionItems[indicator[id]]&paging=false" 2>/dev/null)

# 4. Get Population Data Element ID (for verification of numerator)
# This helps the verifier check if the user selected the right data element
POPULATION_DE_JSON=$(dhis2_api "dataElements?filter=name:ilike:Population&fields=id,name&paging=false" 2>/dev/null)

# Combine into a single JSON result
python3 -c "
import json
import sys

try:
    constants_data = json.loads('''$CONSTANTS_JSON''')
    indicators_data = json.loads('''$INDICATORS_JSON''')
    visualizations_data = json.loads('''$VISUALIZATIONS_JSON''')
    pop_data = json.loads('''$POPULATION_DE_JSON''')
    
    result = {
        'task_start_iso': '$TASK_START_ISO',
        'constants': constants_data.get('constants', []),
        'indicators': indicators_data.get('indicators', []),
        'visualizations': visualizations_data.get('visualizations', []),
        'population_data_elements': pop_data.get('dataElements', []),
        'export_timestamp': '$(date -Iseconds)'
    }
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/constant_task_result.json

chmod 666 /tmp/constant_task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/constant_task_result.json"
cat /tmp/constant_task_result.json
echo ""
echo "=== Export Complete ==="