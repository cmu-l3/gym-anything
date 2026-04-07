#!/bin/bash
set -e
echo "=== Exporting create_conversion_rate results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_rate_count.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 3. Query the Database for the result
# We look for the most recently created record that matches criteria
echo "--- Querying database for new conversion rate ---"

# We output the result as a single line JSON object using database string functions if possible,
# or just select fields and format with jq/python later. Here we select raw fields.
# Fields: multiplyrate, dividerate, from_iso, to_iso, validfrom, validto, type_name, client_name, created
QUERY_RESULT=$(idempiere_query "
    SELECT 
        cr.multiplyrate || '|' || 
        cr.dividerate || '|' || 
        cf.iso_code || '|' || 
        ct.iso_code || '|' || 
        TO_CHAR(cr.validfrom, 'YYYY-MM-DD') || '|' || 
        TO_CHAR(cr.validto, 'YYYY-MM-DD') || '|' || 
        cyt.name || '|' || 
        cl.name || '|' || 
        EXTRACT(EPOCH FROM cr.created)
    FROM c_conversion_rate cr
    JOIN c_currency cf ON cr.c_currency_id = cf.c_currency_id
    JOIN c_currency ct ON cr.c_currency_id_to = ct.c_currency_id
    JOIN c_conversiontype cyt ON cr.c_conversiontype_id = cyt.c_conversiontype_id
    JOIN ad_client cl ON cr.ad_client_id = cl.ad_client_id
    WHERE cf.iso_code='EUR' AND ct.iso_code='USD'
    AND cr.ad_client_id=${CLIENT_ID:-11}
    ORDER BY cr.created DESC LIMIT 1
" 2>/dev/null || echo "")

# 4. Parse Query Result
FOUND="false"
MULTIPLY_RATE="0"
DIVIDE_RATE="0"
CUR_FROM=""
CUR_TO=""
VALID_FROM=""
VALID_TO=""
CONV_TYPE=""
CLIENT_NAME=""
CREATED_TS="0"

if [ -n "$QUERY_RESULT" ] && [ "$QUERY_RESULT" != "0" ]; then
    FOUND="true"
    IFS='|' read -r MULTIPLY_RATE DIVIDE_RATE CUR_FROM CUR_TO VALID_FROM VALID_TO CONV_TYPE CLIENT_NAME CREATED_TS <<< "$QUERY_RESULT"
fi

# 5. Check if record is "new" (created after task start)
IS_NEW="false"
# Use simple integer comparison for timestamps
if [ "${CREATED_TS%.*}" -gt "$TASK_START" ] 2>/dev/null; then
    IS_NEW="true"
fi

# 6. Check if window title suggests success/correct location
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# 7. Construct JSON Result
# Use python to safely generate JSON to avoid quoting issues
python3 -c "
import json
import sys

data = {
    'record_found': $FOUND,
    'record_details': {
        'multiply_rate': float('$MULTIPLY_RATE') if '$MULTIPLY_RATE' else 0,
        'divide_rate': float('$DIVIDE_RATE') if '$DIVIDE_RATE' else 0,
        'currency_from': '$CUR_FROM',
        'currency_to': '$CUR_TO',
        'valid_from': '$VALID_FROM',
        'valid_to': '$VALID_TO',
        'conversion_type': '$CONV_TYPE',
        'client_name': '$CLIENT_NAME',
        'created_timestamp': float('$CREATED_TS') if '$CREATED_TS' else 0
    },
    'meta': {
        'task_start_time': $TASK_START,
        'initial_count': $INITIAL_COUNT,
        'is_newly_created': $IS_NEW,
        'final_window_title': '$WINDOW_TITLE',
        'screenshot_path': '/tmp/task_final.png'
    }
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

# 8. Set permissions so the host can read it (if volume mounted, though copy_from_env handles this)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="