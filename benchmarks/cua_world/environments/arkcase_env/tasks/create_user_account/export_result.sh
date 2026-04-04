#!/bin/bash
echo "=== Exporting Create User Account Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Identify LDAP Pod
LDAP_POD=$(kubectl get pods -n arkcase --no-headers 2>/dev/null | grep ldap | awk '{print $1}' | head -1)

# Initialize result variables
USER_EXISTS="false"
USER_DN=""
GIVEN_NAME=""
SN=""
MAIL=""
WHEN_CREATED=""
IN_GROUP="false"
API_VERIFIED="false"

if [ -n "$LDAP_POD" ]; then
    echo "Querying LDAP pod: $LDAP_POD"
    
    # Check User Existence
    if kubectl exec -n arkcase "$LDAP_POD" -- samba-tool user list 2>/dev/null | grep -q "elena.rodriguez"; then
        USER_EXISTS="true"
        
        # Get User Details
        USER_INFO=$(kubectl exec -n arkcase "$LDAP_POD" -- samba-tool user show elena.rodriguez 2>/dev/null)
        
        # Parse attributes (careful with whitespace)
        USER_DN=$(echo "$USER_INFO" | grep "^dn:" | sed 's/^dn: //')
        GIVEN_NAME=$(echo "$USER_INFO" | grep "^givenName:" | sed 's/^givenName: //')
        SN=$(echo "$USER_INFO" | grep "^sn:" | sed 's/^sn: //')
        MAIL=$(echo "$USER_INFO" | grep "^mail:" | sed 's/^mail: //')
        WHEN_CREATED=$(echo "$USER_INFO" | grep "^whenCreated:" | sed 's/^whenCreated: //')
        
        # Check Group Membership
        # 'samba-tool group listmembers' lists usernames
        if kubectl exec -n arkcase "$LDAP_POD" -- samba-tool group listmembers "ACM_INVESTIGATOR_DEV" 2>/dev/null | grep -q "elena.rodriguez"; then
            IN_GROUP="true"
        fi
    fi
else
    echo "ERROR: LDAP pod not found during export."
fi

# Verify via ArkCase API (Application Layer check)
echo "Verifying via ArkCase API..."
ensure_portforward
API_RESPONSE=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    "${ARKCASE_URL}/api/v1/users/elena.rodriguez@dev.arkcase.com" 2>/dev/null || echo "")

# If API returns a valid JSON with the username, it's verified
if echo "$API_RESPONSE" | grep -q "elena.rodriguez"; then
    API_VERIFIED="true"
fi

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "ldap_user_exists": $USER_EXISTS,
    "ldap_attributes": {
        "givenName": "$GIVEN_NAME",
        "sn": "$SN",
        "mail": "$MAIL",
        "whenCreated": "$WHEN_CREATED"
    },
    "group_membership": {
        "target_group": "ACM_INVESTIGATOR_DEV",
        "is_member": $IN_GROUP
    },
    "api_verification": {
        "user_found": $API_VERIFIED
    },
    "screenshots": {
        "initial": "/tmp/task_initial.png",
        "final": "/tmp/task_final.png"
    }
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="