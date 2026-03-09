#!/bin/bash
echo "=== Exporting add_customer_alt_email result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target Data
CUST_FIRST="Dr. Julian"
CUST_LAST="Blackwood"
NEW_EMAIL="j.blackwood@nexus-corp.com"
ORIG_EMAIL="julian.b@university.local"

# 1. Find Customer ID
CUSTOMER_DATA=$(find_customer_by_name "$CUST_FIRST" "$CUST_LAST")
CUST_ID=""
CUST_FOUND="false"

if [ -n "$CUSTOMER_DATA" ]; then
    CUST_FOUND="true"
    CUST_ID=$(echo "$CUSTOMER_DATA" | cut -f1)
fi

# 2. Get All Emails for this Customer
EMAILS_JSON="[]"
EMAIL_COUNT=0
HAS_NEW_EMAIL="false"
HAS_ORIG_EMAIL="false"

if [ "$CUST_FOUND" = "true" ] && [ -n "$CUST_ID" ]; then
    # Raw SQL to get emails
    RAW_EMAILS=$(fs_query "SELECT email FROM emails WHERE customer_id = $CUST_ID")
    
    # Process into JSON array and check content
    # fs_query returns newline separated list
    EMAILS_ARRAY=()
    while IFS= read -r email; do
        if [ -n "$email" ]; then
            # Clean whitespace
            email=$(echo "$email" | xargs)
            EMAILS_ARRAY+=("\"$email\"")
            
            # Check matches (case insensitive)
            if echo "$email" | grep -qi "^$NEW_EMAIL$"; then
                HAS_NEW_EMAIL="true"
            fi
            if echo "$email" | grep -qi "^$ORIG_EMAIL$"; then
                HAS_ORIG_EMAIL="true"
            fi
        fi
    done <<< "$RAW_EMAILS"
    
    # Join array with commas
    EMAILS_JSON="[$(IFS=,; echo "${EMAILS_ARRAY[*]}")]"
    EMAIL_COUNT=${#EMAILS_ARRAY[@]}
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "customer_found": $CUST_FOUND,
    "customer_id": "${CUST_ID}",
    "emails": $EMAILS_JSON,
    "email_count": $EMAIL_COUNT,
    "has_new_email": $HAS_NEW_EMAIL,
    "has_original_email": $HAS_ORIG_EMAIL,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="