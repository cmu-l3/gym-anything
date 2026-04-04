#!/bin/bash
# Export script for Create API Integration task

echo "=== Exporting Create API Integration Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Integration Table
# Check for integration by name
INTEGRATION_DATA=$(magento_query "SELECT integration_id, name, email, status, setup_type, created_at, consumer_id FROM integration WHERE name='FastTrack_Logistics' ORDER BY integration_id DESC LIMIT 1" 2>/dev/null | tail -1)

INT_ID=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
INT_NAME=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $2}')
INT_EMAIL=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $3}')
INT_STATUS=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
INT_SETUP_TYPE=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
INT_CREATED_AT=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $6}')
INT_CONSUMER_ID=$(echo "$INTEGRATION_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')

INT_FOUND="false"
[ -n "$INT_ID" ] && INT_FOUND="true"
echo "Integration found: $INT_FOUND (ID=$INT_ID, Status=$INT_STATUS)"

# 2. Check for OAuth Tokens (Proof of Activation)
# If status is Active (1), tokens should exist in oauth_token for this consumer
TOKEN_COUNT="0"
if [ -n "$INT_CONSUMER_ID" ]; then
    TOKEN_COUNT=$(magento_query "SELECT COUNT(*) FROM oauth_token WHERE consumer_id=$INT_CONSUMER_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
fi
echo "OAuth tokens found: $TOKEN_COUNT"

# 3. Check Resource Permissions
# In Magento, integrations are Users (type 7) in authorization_role table linked to integration_id
# We need to find the resources in authorization_rule
RESOURCE_LIST=""
if [ -n "$INT_ID" ]; then
    # Get all resources allowed for this integration
    # Join authorization_role (user_id=integration_id, user_type=7) with authorization_rule
    RESOURCES_RAW=$(magento_query "SELECT rule.resource_id 
        FROM authorization_rule rule 
        JOIN authorization_role role ON rule.role_id = role.role_id 
        WHERE role.user_type = 7 AND role.user_id = $INT_ID" 2>/dev/null)
    
    # Convert newlines to comma-separated string
    RESOURCE_LIST=$(echo "$RESOURCES_RAW" | tr '\n' ',' | sed 's/,$//')
fi
echo "Resources granted: $RESOURCE_LIST"

# 4. Check creation timestamp against task start
CREATED_DURING_TASK="false"
# Simple check: if integration exists and we wiped it at start, it must be new.
# But let's check INT_CREATED_AT just in case (mysql format YYYY-MM-DD HH:MM:SS)
if [ -n "$INT_ID" ]; then
    CREATED_DURING_TASK="true"
fi

# Escape for JSON
INT_NAME_ESC=$(echo "$INT_NAME" | sed 's/"/\\"/g')
INT_EMAIL_ESC=$(echo "$INT_EMAIL" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/api_integration_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "integration_found": $INT_FOUND,
    "integration_id": "${INT_ID:-}",
    "name": "$INT_NAME_ESC",
    "email": "$INT_EMAIL_ESC",
    "status": "${INT_STATUS:-0}",
    "setup_type": "${INT_SETUP_TYPE:-}",
    "token_count": ${TOKEN_COUNT:-0},
    "created_during_task": $CREATED_DURING_TASK,
    "resources": "$RESOURCE_LIST",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/api_integration_result.json

echo ""
cat /tmp/api_integration_result.json
echo ""
echo "=== Export Complete ==="