#!/bin/bash
echo "=== Exporting add_case_costs results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Basic Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CASE_ID=$(cat /tmp/arkcase_case_id.txt 2>/dev/null || echo "")

# 3. Verify Report File
REPORT_PATH="/home/ga/Documents/cost_tracking_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 20) # Read first 20 lines
    
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 4. API Verification of Costs
# We attempt to retrieve the costs associated with the case via API
# Endpoint assumption: GET /api/v1/plugin/complaint/{id}/expenses OR /api/v1/case/{id}/costs
# Since ArkCase API specifics can vary, we try a standard endpoint pattern or search.
# For this task, we will attempt to query the 'complaint' endpoint which often includes children/expenses.

echo "Querying API for case expenses..."
API_RESPONSE=$(arkcase_api GET "plugin/complaint/${CASE_ID}" 2>/dev/null)

# Save raw response for debugging/verifier
echo "$API_RESPONSE" > /tmp/api_response_debug.json

# Extract relevant fields using Python for robustness
# We are looking for an 'expenses', 'costs', or 'lineItems' array in the response
# If the main call doesn't have it, we might check a sub-endpoint (simulated here by checking generic structure)
COST_DATA=$(python3 -c "
import sys, json
try:
    data = json.load(open('/tmp/api_response_debug.json'))
    # Look for expenses list. 
    # In many case management systems, this is a related list.
    # If not present directly, we simulate finding it (or return empty if not found).
    # For this exercise, we assume 'expenses' is a key in the case object or a related endpoint was called.
    
    # If standard API doesn't return nested expenses, we would usually call:
    # GET /api/v1/plugin/complaint/{id}/expenses
    # Let's assume the previous bash command might have needed to be that.
    
    expenses = data.get('expenses', [])
    if not expenses and 'costSheet' in data:
        expenses = data['costSheet'].get('lineItems', [])
        
    print(json.dumps(expenses))
except Exception:
    print('[]')
")

# If the first attempt yielded nothing, try a specific expenses endpoint
if [ "$COST_DATA" == "[]" ] || [ "$COST_DATA" == "" ]; then
    EXPENSES_RESPONSE=$(arkcase_api GET "plugin/complaint/${CASE_ID}/expenses" 2>/dev/null)
    if [ -n "$EXPENSES_RESPONSE" ] && [ "$EXPENSES_RESPONSE" != "null" ]; then
         COST_DATA="$EXPENSES_RESPONSE"
    fi
fi

# 5. Construct JSON Result
# We embed the cost data and file status into a JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_snippet": $(echo "$REPORT_CONTENT" | jq -R -s '.')
    },
    "api_data": {
        "costs": $COST_DATA
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="