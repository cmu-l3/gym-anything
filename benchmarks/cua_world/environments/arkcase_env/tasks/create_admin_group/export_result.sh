#!/bin/bash
# post_task: Export results for create_admin_group task

echo "=== Exporting create_admin_group results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")
GROUP_NAME="FOIA_Senior_Analysts"

# Check LDAP (Primary signal)
echo "Checking LDAP for group '$GROUP_NAME'..."
LDAP_CHECK=$(kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool group list 2>/dev/null | grep -i "^${GROUP_NAME}$" || echo "")
LDAP_EXISTS="false"
if [ -n "$LDAP_CHECK" ]; then
    LDAP_EXISTS="true"
fi

# Get LDAP Details (Description/Members)
LDAP_DETAILS=""
if [ "$LDAP_EXISTS" = "true" ]; then
    LDAP_DETAILS=$(kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool group show "$GROUP_NAME" 2>/dev/null || echo "")
fi

# Check API (Secondary signal)
echo "Checking ArkCase API..."
# We try to fetch the group via REST API
API_RESPONSE=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    "https://localhost:9443/arkcase/api/v1/users/groups" 2>/dev/null || echo "")

API_EXISTS="false"
if echo "$API_RESPONSE" | grep -q "$GROUP_NAME"; then
    API_EXISTS="true"
fi

# Check total count change
FINAL_COUNT=$(kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool group list 2>/dev/null | wc -l || echo "0")
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "group_name": "$GROUP_NAME",
    "ldap_exists": $LDAP_EXISTS,
    "api_exists": $API_EXISTS,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_diff": $COUNT_DIFF,
    "ldap_details": $(echo "$LDAP_DETAILS" | jq -R -s '.' 2>/dev/null || echo "\"\""),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="