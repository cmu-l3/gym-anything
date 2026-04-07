#!/bin/bash
set -e
echo "=== Exporting task results: record_customer_payment ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ----------------------------------------------------------------
# Database Verification Logic
# ----------------------------------------------------------------

# 1. Get current count
CURRENT_PAYMENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_payment WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_payment_count.txt 2>/dev/null || echo "0")

# 2. Identify the specific record created by the agent
# Strategy: Find payments created/updated after task start AND not in the initial ID list
# We also filter for the specific amount/BP to be helpful, but we return whatever we find to the verifier
# so it can decide if it's correct or not.

# Helper to get BP ID for Joe Block
BP_ID=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name='Joe Block' AND ad_client_id=$CLIENT_ID LIMIT 1" 2>/dev/null || echo "0")

# Find candidate payments:
# - Must be in GardenWorld client
# - Must NOT be in the exclusion list (existing_payment_ids.txt)
# - Sort by ID descending (newest first)
EXCLUSION_LIST=$(cat /tmp/existing_payment_ids.txt 2>/dev/null | tr '\n' ',' | sed 's/,$//')
if [ -z "$EXCLUSION_LIST" ]; then EXCLUSION_LIST="0"; fi

NEW_PAYMENT_ID=$(idempiere_query "SELECT c_payment_id FROM c_payment WHERE ad_client_id=$CLIENT_ID AND c_payment_id NOT IN ($EXCLUSION_LIST) ORDER BY c_payment_id DESC LIMIT 1" 2>/dev/null || echo "")

# If no new ID found, try searching by criteria as a fallback (in case ID logic failed)
if [ -z "$NEW_PAYMENT_ID" ]; then
    NEW_PAYMENT_ID=$(idempiere_query "SELECT c_payment_id FROM c_payment WHERE ad_client_id=$CLIENT_ID AND c_bpartner_id=$BP_ID AND payamt=1750.00 ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "")
fi

# 3. Extract details for the found payment
PAYMENT_FOUND="false"
DETAILS="{}"

if [ -n "$NEW_PAYMENT_ID" ]; then
    PAYMENT_FOUND="true"
    
    # Query all relevant fields
    # Using specific formatting to ensure clean JSON strings
    RAW_DATA=$(idempiere_query "SELECT 
        p.payamt, 
        p.isreceipt, 
        p.tendertype, 
        p.checkno, 
        p.docstatus, 
        bp.name,
        EXTRACT(EPOCH FROM p.created)::bigint
        FROM c_payment p
        LEFT JOIN c_bpartner bp ON p.c_bpartner_id = bp.c_bpartner_id
        WHERE p.c_payment_id=$NEW_PAYMENT_ID" 2>/dev/null)
    
    # Parse pipe-separated values (default psql format with -A -t is pipe? No, usually pipe if specified, but idempiere_query uses -A -t which implies pipe for aligned? 
    # Actually idempiere_query uses -A (unaligned) which defaults to pipe '|' separator.
    
    AMT=$(echo "$RAW_DATA" | cut -d'|' -f1)
    IS_RECEIPT=$(echo "$RAW_DATA" | cut -d'|' -f2)
    TENDER_TYPE=$(echo "$RAW_DATA" | cut -d'|' -f3)
    CHECK_NO=$(echo "$RAW_DATA" | cut -d'|' -f4)
    DOC_STATUS=$(echo "$RAW_DATA" | cut -d'|' -f5)
    BP_NAME=$(echo "$RAW_DATA" | cut -d'|' -f6)
    CREATED_TS=$(echo "$RAW_DATA" | cut -d'|' -f7)

    # Construct JSON object for the record
    DETAILS="{\"id\": $NEW_PAYMENT_ID, \"amount\": \"$AMT\", \"is_receipt\": \"$IS_RECEIPT\", \"tender_type\": \"$TENDER_TYPE\", \"check_no\": \"$CHECK_NO\", \"doc_status\": \"$DOC_STATUS\", \"bp_name\": \"$BP_NAME\", \"created_ts\": $CREATED_TS}"
fi

# 4. Generate Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_PAYMENT_COUNT,
    "payment_found": $PAYMENT_FOUND,
    "payment_details": $DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="