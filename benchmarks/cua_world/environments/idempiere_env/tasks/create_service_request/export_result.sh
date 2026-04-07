#!/bin/bash
set -e
echo "=== Exporting Create Service Request result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CLIENT_ID=$(get_gardenworld_client_id)
JOE_BLOCK_ID=$(cat /tmp/joe_block_id.txt 2>/dev/null || echo "0")

# 2. Get current counts
INITIAL_COUNT=$(cat /tmp/initial_request_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM r_request WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# 3. Search for the specific request created during the task
# We look for:
# - Created after start time
# - Summary containing "paint peeling" (case insensitive)
# - Valid Client ID

echo "Searching for created request..."

# Construct SQL query for validation
# Notes on iDempiere R_Request columns:
# - Priority: '1'=Urgent, '3'=High, '5'=Medium, '7'=Low, '9'=Minor
# - ConfidentialType: 'A'=Public, 'C'=Customer, 'I'=Internal, 'P'=Private

QUERY="
SELECT 
    r_request_id,
    summary,
    priority,
    confidentialtype,
    c_bpartner_id,
    created
FROM r_request 
WHERE 
    ad_client_id=$CLIENT_ID 
    AND created >= to_timestamp($TASK_START)
    AND summary ILIKE '%paint peeling%'
ORDER BY created DESC 
LIMIT 1
"

RESULT_ROW=$(idempiere_query "$QUERY" 2>/dev/null || echo "")

# Parse the result
FOUND_REQUEST="false"
REQ_SUMMARY=""
REQ_PRIORITY=""
REQ_CONFIDENTIALITY=""
REQ_BP_ID=""
REQ_CREATED=""

if [ -n "$RESULT_ROW" ]; then
    FOUND_REQUEST="true"
    # Result is pipe or bar separated usually, but idempiere_query uses psql default (pipe)
    # We'll rely on the fact we asked for specific columns in order.
    # psql -A -t output is "col1|col2|..."
    
    IFS='|' read -r ID SUM PRI CONF BP CREATED <<< "$RESULT_ROW"
    
    REQ_SUMMARY="$SUM"
    REQ_PRIORITY="$PRI"
    REQ_CONFIDENTIALITY="$CONF"
    REQ_BP_ID="$BP"
    REQ_CREATED="$CREATED"
fi

# 4. Fallback: If not found by summary, check if ANY request was created for Joe Block
if [ "$FOUND_REQUEST" = "false" ]; then
    FALLBACK_QUERY="SELECT summary, created FROM r_request WHERE ad_client_id=$CLIENT_ID AND created >= to_timestamp($TASK_START) AND c_bpartner_id=$JOE_BLOCK_ID ORDER BY created DESC LIMIT 1"
    FALLBACK_ROW=$(idempiere_query "$FALLBACK_QUERY" 2>/dev/null || echo "")
    if [ -n "$FALLBACK_ROW" ]; then
        IFS='|' read -r SUM CREATED <<< "$FALLBACK_ROW"
        REQ_SUMMARY_FALLBACK="$SUM"
    fi
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "found_request": $FOUND_REQUEST,
    "request_details": {
        "summary": "$(echo "$REQ_SUMMARY" | sed 's/"/\\"/g')",
        "priority": "$REQ_PRIORITY",
        "confidentiality": "$REQ_CONFIDENTIALITY",
        "bpartner_id": "$REQ_BP_ID",
        "expected_bp_id": "$JOE_BLOCK_ID"
    },
    "fallback_summary": "$(echo "${REQ_SUMMARY_FALLBACK:-}" | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="