#!/bin/bash
echo "=== Exporting create_gl_budget result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CLIENT_ID=$(get_gardenworld_client_id)

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "--- Querying Database for Result ---"

# We need to extract the budget header and its lines
# We return a JSON object constructed via jq or python, but here we'll use a temp file and python for robust JSON creation

# 1. Fetch Budget Header
# We look for the specific name created during the task (after start time ideally, but filtering by name is primary)
# We select the most recently created one if multiple exist (though setup cleaned them)
BUDGET_JSON=$(idempiere_query "
    SELECT row_to_json(t)
    FROM (
        SELECT 
            gl_budget_id, 
            name, 
            description, 
            isactive, 
            created 
        FROM gl_budget 
        WHERE name = '2025 Operating Budget' 
          AND ad_client_id = ${CLIENT_ID:-11}
        ORDER BY created DESC 
        LIMIT 1
    ) t
" 2>/dev/null || echo "")

# 2. Fetch Budget Lines if header exists
LINES_JSON="[]"
if [ -n "$BUDGET_JSON" ] && [ "$BUDGET_JSON" != "" ]; then
    BUDGET_ID=$(echo "$BUDGET_JSON" | jq -r .gl_budget_id)
    
    # Query lines joining with valid combination and element value to get account names
    # Complex query to get meaningful data for verification
    LINES_JSON=$(idempiere_query "
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT 
                bl.gl_budgetline_id,
                bl.amt,
                bl.created,
                ev.value as account_value,
                ev.name as account_name,
                vc.combination as alias
            FROM gl_budgetline bl
            JOIN c_validcombination vc ON bl.c_validcombination_id = vc.c_validcombination_id
            JOIN c_elementvalue ev ON vc.account_id = ev.c_elementvalue_id
            WHERE bl.gl_budget_id = $BUDGET_ID
        ) t
    " 2>/dev/null || echo "[]")
fi

# Handle empty results
if [ -z "$BUDGET_JSON" ]; then BUDGET_JSON="null"; fi
if [ -z "$LINES_JSON" ]; then LINES_JSON="[]"; fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    budget = $BUDGET_JSON
    lines = $LINES_JSON
except:
    budget = None
    lines = []

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'budget_found': budget is not None,
    'budget': budget,
    'lines': lines,
    'line_count': len(lines) if lines else 0,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="