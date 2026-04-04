#!/bin/bash
set -e
echo "=== Exporting merge_duplicate_tickets result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot "/tmp/task_final.png"

CUSTOMER_EMAIL="alice.chen@example.org"

# 1. Get Active Conversations for Customer
# Status: 1=Active, 2=Pending. (Merged tickets are usually deleted or marked with status=5 (merged) or closed)
# We want to find the ONE survivor.
CONV_IDS=$(fs_query "
SELECT c.id 
FROM conversations c 
JOIN customers cust ON c.customer_id = cust.id 
JOIN emails e ON cust.id = e.customer_id 
WHERE e.email = '$CUSTOMER_EMAIL' 
AND c.status IN (1, 2)
")

# Count how many lines/IDs returned
# fs_query returns raw output, one ID per line if multiple
CONV_COUNT=0
if [ -n "$CONV_IDS" ]; then
    CONV_COUNT=$(echo "$CONV_IDS" | grep -cve '^\s*$')
fi

# Identify survivor ID (take the first one if multiple, though >1 is a partial fail)
SURVIVOR_ID=$(echo "$CONV_IDS" | head -n 1 | tr -d ' \r\n')

# 2. Check Content Preservation
# We check if the survivor contains the text from all 3 original emails
TEXT_1="checking on my shipment"
TEXT_2="wrong zip code"
TEXT_3="apartment number 4B"

FOUND_1="false"
FOUND_2="false"
FOUND_3="false"

if [ -n "$SURVIVOR_ID" ]; then
    # Helper to check text in threads of a conversation
    check_text() {
        local cid="$1"
        local txt="$2"
        # Search threads body
        local count
        count=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $cid AND body LIKE '%$txt%'")
        if [ "$count" -gt "0" ]; then echo "true"; else echo "false"; fi
    }
    
    FOUND_1=$(check_text "$SURVIVOR_ID" "$TEXT_1")
    FOUND_2=$(check_text "$SURVIVOR_ID" "$TEXT_2")
    FOUND_3=$(check_text "$SURVIVOR_ID" "$TEXT_3")
fi

# 3. Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "active_conversation_count": ${CONV_COUNT},
    "survivor_id": "${SURVIVOR_ID}",
    "found_text_1": ${FOUND_1},
    "found_text_2": ${FOUND_2},
    "found_text_3": ${FOUND_3},
    "customer_email": "${CUSTOMER_EMAIL}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="