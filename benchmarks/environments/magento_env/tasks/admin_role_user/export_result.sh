#!/bin/bash
# Export script for Admin Role & User task

echo "=== Exporting Admin Role & User Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")

CURRENT_ROLE_COUNT=$(magento_query "SELECT COUNT(*) FROM authorization_role WHERE role_type='G'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
CURRENT_USER_COUNT=$(magento_query "SELECT COUNT(*) FROM admin_user" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# ==============================================================================
# 1. VERIFY ROLE
# ==============================================================================
echo "Checking for role 'Customer Service Lead'..."
ROLE_DATA=$(magento_query "SELECT role_id, role_name FROM authorization_role WHERE role_name='Customer Service Lead' AND role_type='G'" 2>/dev/null | tail -1)

ROLE_FOUND="false"
ROLE_ID=""
ROLE_NAME=""
PERMISSIONS_JSON="[]"

if [ -n "$ROLE_DATA" ]; then
    ROLE_FOUND="true"
    ROLE_ID=$(echo "$ROLE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    ROLE_NAME=$(echo "$ROLE_DATA" | awk -F'\t' '{print $2}')
    
    echo "Role found: ID=$ROLE_ID, Name='$ROLE_NAME'"
    
    # Get permissions for this role
    # usage: check authorization_rule table
    # We are looking for specific resource_ids
    echo "Fetching permissions..."
    
    # Check for specific key resources
    # We construct a simple JSON array of allowed resources
    ALLOWED_RESOURCES=$(magento_query "SELECT resource_id FROM authorization_rule WHERE role_id=$ROLE_ID AND permission='allow'" 2>/dev/null)
    
    # Convert newline separated list to JSON array
    PERMISSIONS_JSON=$(echo "$ALLOWED_RESOURCES" | jq -R . | jq -s .)
else
    echo "Role NOT found."
fi

# ==============================================================================
# 2. VERIFY USER
# ==============================================================================
echo "Checking for user 'cs_lead_jones'..."
USER_DATA=$(magento_query "SELECT user_id, username, firstname, lastname, email, is_active, created FROM admin_user WHERE username='cs_lead_jones'" 2>/dev/null | tail -1)

USER_FOUND="false"
USER_ID=""
USER_USERNAME=""
USER_FIRSTNAME=""
USER_LASTNAME=""
USER_EMAIL=""
USER_ACTIVE=""
USER_CREATED=""

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    USER_ID=$(echo "$USER_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    USER_USERNAME=$(echo "$USER_DATA" | awk -F'\t' '{print $2}')
    USER_FIRSTNAME=$(echo "$USER_DATA" | awk -F'\t' '{print $3}')
    USER_LASTNAME=$(echo "$USER_DATA" | awk -F'\t' '{print $4}')
    USER_EMAIL=$(echo "$USER_DATA" | awk -F'\t' '{print $5}')
    USER_ACTIVE=$(echo "$USER_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
    USER_CREATED=$(echo "$USER_DATA" | awk -F'\t' '{print $7}')
    
    echo "User found: ID=$USER_ID, Name='$USER_FIRSTNAME $USER_LASTNAME', Email='$USER_EMAIL'"
else
    echo "User NOT found."
fi

# ==============================================================================
# 3. VERIFY ASSIGNMENT
# ==============================================================================
ASSIGNMENT_CORRECT="false"
ASSIGNED_ROLE_ID=""

if [ "$USER_FOUND" = "true" ] && [ "$ROLE_FOUND" = "true" ]; then
    # Check authorization_role table for role_type='U' linking user_id to parent_id (role_id)
    # The parent_id in this table for role_type='U' points to the role_id of the group role
    ASSIGNMENT_DATA=$(magento_query "SELECT parent_id FROM authorization_role WHERE user_id=$USER_ID AND role_type='U'" 2>/dev/null | tail -1 | tr -d '[:space:]')
    
    ASSIGNED_ROLE_ID="$ASSIGNMENT_DATA"
    
    if [ "$ASSIGNED_ROLE_ID" = "$ROLE_ID" ]; then
        ASSIGNMENT_CORRECT="true"
        echo "User correctly assigned to role ID $ROLE_ID"
    else
        echo "User assigned to wrong role ID: $ASSIGNED_ROLE_ID (Expected: $ROLE_ID)"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/admin_role_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_role_count": ${INITIAL_ROLE_COUNT:-0},
    "current_role_count": ${CURRENT_ROLE_COUNT:-0},
    "initial_user_count": ${INITIAL_USER_COUNT:-0},
    "current_user_count": ${CURRENT_USER_COUNT:-0},
    "role_found": $ROLE_FOUND,
    "role": {
        "id": "${ROLE_ID:-}",
        "name": "${ROLE_NAME:-}",
        "allowed_resources": ${PERMISSIONS_JSON:-[]}
    },
    "user_found": $USER_FOUND,
    "user": {
        "id": "${USER_ID:-}",
        "username": "${USER_USERNAME:-}",
        "firstname": "${USER_FIRSTNAME:-}",
        "lastname": "${USER_LASTNAME:-}",
        "email": "${USER_EMAIL:-}",
        "is_active": "${USER_ACTIVE:-}",
        "created_at": "${USER_CREATED:-}"
    },
    "assignment_correct": $ASSIGNMENT_CORRECT,
    "assigned_role_id": "${ASSIGNED_ROLE_ID:-}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/admin_role_result.json

echo ""
cat /tmp/admin_role_result.json
echo ""
echo "=== Export Complete ==="