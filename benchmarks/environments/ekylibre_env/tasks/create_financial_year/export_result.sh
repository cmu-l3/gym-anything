#!/bin/bash
set -e
echo "=== Exporting task result: Create Financial Year 2017 ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_FY_COUNT=$(cat /tmp/initial_fy_count.txt 2>/dev/null || echo "0")
TENANT_SCHEMA=$(cat /tmp/ekylibre_tenant_schema.txt 2>/dev/null || echo "demo")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the 2017 financial year
# We select creation timestamp as epoch to verify it was created during the task
echo "Querying database for 2017 financial year..."
FY_JSON=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c \
    "SET search_path TO ${TENANT_SCHEMA}, public; 
     SELECT row_to_json(t) FROM (
        SELECT id, 
               started_on, 
               stopped_on, 
               currency, 
               EXTRACT(EPOCH FROM created_at)::bigint as created_at_epoch 
        FROM financial_years 
        WHERE started_on = '2017-01-01' 
        AND stopped_on = '2017-12-31'
        LIMIT 1
     ) t;" 2>/dev/null || echo "{}")

# If empty (no record found), set to null/empty json
if [ -z "$FY_JSON" ]; then
    FY_JSON="null"
fi

# Get current count
CURRENT_FY_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c \
    "SET search_path TO ${TENANT_SCHEMA}, public; SELECT COUNT(*) FROM financial_years;" 2>/dev/null || echo "0")

# Construct result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_fy_count": $INITIAL_FY_COUNT,
    "current_fy_count": $CURRENT_FY_COUNT,
    "found_record": $FY_JSON,
    "tenant_schema": "$TENANT_SCHEMA",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (handling permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="