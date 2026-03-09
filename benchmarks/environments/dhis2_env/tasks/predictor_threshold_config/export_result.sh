#!/bin/bash
# Export script for Predictor Threshold Configuration task

echo "=== Exporting Predictor Threshold Result ==="

source /workspace/scripts/task_utils.sh

# Fallback functions
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

# 1. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Task Start Time
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2024-01-01T00:00:00.000Z")
echo "Task Start (ISO): $TASK_START_ISO"

# 3. Query for Created Data Elements (Filtered by name and created time)
# Note: DHIS2 API filtering by 'created' is supported in recent versions, 
# but filtering by name first is safer, then we check timestamps in python.
echo "Querying new data elements..."
DE_RESULT=$(dhis2_api "dataElements?filter=name:ilike:Threshold&fields=id,name,shortName,domainType,valueType,aggregationType,created&paging=false" 2>/dev/null | \
python3 -c "
import json, sys, datetime

try:
    data = json.load(sys.stdin)
    task_start = '$TASK_START_ISO'
    
    # Simple string comparison for ISO dates usually works if formats match,
    # but let's just find the most relevant one.
    
    candidates = data.get('dataElements', [])
    new_des = []
    
    for de in candidates:
        # Check if created >= task_start (lexicographical comparison for ISO strings works well enough)
        # Or just return all matches and let verifier filter
        new_des.append(de)
        
    print(json.dumps(new_des))
except Exception as e:
    print(json.dumps([]))
")

# 4. Query for Created Predictors
echo "Querying new predictors..."
PRED_RESULT=$(dhis2_api "predictors?filter=name:ilike:Threshold&fields=id,name,periodType,sequentialSampleCount,generator[expression],output[id,name],created&paging=false" 2>/dev/null | \
python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
    print(json.dumps(data.get('predictors', [])))
except Exception as e:
    print(json.dumps([]))
")

# 5. Get counts
INITIAL_DE_COUNT=$(cat /tmp/initial_de_count 2>/dev/null || echo "0")
INITIAL_PRED_COUNT=$(cat /tmp/initial_pred_count 2>/dev/null || echo "0")

CURRENT_DE_COUNT=$(dhis2_api "dataElements?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; print(json.load(sys.stdin).get('pager',{}).get('total',0))" 2>/dev/null || echo "0")

CURRENT_PRED_COUNT=$(dhis2_api "predictors?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; print(json.load(sys.stdin).get('pager',{}).get('total',0))" 2>/dev/null || echo "0")

# 6. Construct Result JSON
cat > /tmp/predictor_threshold_result.json <<EOF
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_de_count": $INITIAL_DE_COUNT,
    "current_de_count": $CURRENT_DE_COUNT,
    "initial_pred_count": $INITIAL_PRED_COUNT,
    "current_pred_count": $CURRENT_PRED_COUNT,
    "candidate_data_elements": $DE_RESULT,
    "candidate_predictors": $PRED_RESULT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/predictor_threshold_result.json

echo "Result JSON content:"
cat /tmp/predictor_threshold_result.json
echo "=== Export Complete ==="