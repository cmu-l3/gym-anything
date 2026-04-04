#!/bin/bash
# Export script for create_user task (post_task hook)
# Gathers verification data and exports to JSON

echo "=== Exporting create_user result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial count
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")

# Get current count
CURRENT_USER_COUNT=$(get_user_count)

echo "Initial user count: $INITIAL_USER_COUNT"
echo "Current user count: $CURRENT_USER_COUNT"

# Expected values
EXPECTED_USERNAME="marketing_lead"
EXPECTED_EMAIL="marketing@example.com"
EXPECTED_FIRST_NAME="Sarah"
EXPECTED_LAST_NAME="Johnson"
EXPECTED_ROLE="editor"

# Initialize result variables
USER_FOUND="false"
USER_ID=""
USERNAME=""
EMAIL=""
FIRST_NAME=""
LAST_NAME=""
DISPLAY_NAME=""
USER_ROLE=""

# Search for the user by username
USER_ID=$(wp_db_query "SELECT ID FROM wp_users WHERE LOWER(user_login) = LOWER('$EXPECTED_USERNAME') LIMIT 1")

# If not found by exact username, try by email
if [ -z "$USER_ID" ]; then
    echo "Username not found, trying by email..."
    USER_ID=$(wp_db_query "SELECT ID FROM wp_users WHERE LOWER(user_email) = LOWER('$EXPECTED_EMAIL') LIMIT 1")
fi

# NOTE: Removed "any new user" fallback - agent MUST create user with correct username/email
# This prevents adversarial bypass where agent creates a random user
if [ -z "$USER_ID" ] && [ "$CURRENT_USER_COUNT" -gt "$INITIAL_USER_COUNT" ]; then
    echo "WARNING: New user(s) created but username/email does not match expected"
    echo "Expected username: $EXPECTED_USERNAME or email: $EXPECTED_EMAIL"
    # Do NOT fall back to any new user - this would enable bypass
fi

if [ -n "$USER_ID" ]; then
    USER_FOUND="true"
    echo "Found user with ID: $USER_ID"

    # Get user details
    USERNAME=$(wp_db_query "SELECT user_login FROM wp_users WHERE ID=$USER_ID")
    EMAIL=$(wp_db_query "SELECT user_email FROM wp_users WHERE ID=$USER_ID")
    DISPLAY_NAME=$(wp_db_query "SELECT display_name FROM wp_users WHERE ID=$USER_ID")

    # Get first and last name from user meta
    FIRST_NAME=$(wp_db_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$USER_ID AND meta_key='first_name'")
    LAST_NAME=$(wp_db_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$USER_ID AND meta_key='last_name'")

    # Get user role using WP-CLI (more reliable)
    cd /var/www/html/wordpress
    USER_ROLE=$(wp user get "$USER_ID" --field=roles --allow-root 2>/dev/null || echo "")

    # Fallback: get role from capabilities meta
    if [ -z "$USER_ROLE" ]; then
        CAPABILITIES=$(wp_db_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$USER_ID AND meta_key='wp_capabilities'")
        if echo "$CAPABILITIES" | grep -qi "editor"; then
            USER_ROLE="editor"
        elif echo "$CAPABILITIES" | grep -qi "administrator"; then
            USER_ROLE="administrator"
        elif echo "$CAPABILITIES" | grep -qi "author"; then
            USER_ROLE="author"
        elif echo "$CAPABILITIES" | grep -qi "subscriber"; then
            USER_ROLE="subscriber"
        fi
    fi

    echo "Username: $USERNAME"
    echo "Email: $EMAIL"
    echo "First name: $FIRST_NAME"
    echo "Last name: $LAST_NAME"
    echo "Display name: $DISPLAY_NAME"
    echo "Role: $USER_ROLE"
else
    echo "No matching user found"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_user_count": $INITIAL_USER_COUNT,
    "current_user_count": $CURRENT_USER_COUNT,
    "user_found": $USER_FOUND,
    "user": {
        "id": "${USER_ID:-}",
        "username": "$(echo "$USERNAME" | sed 's/"/\\"/g' | tr -d '\n')",
        "email": "$(echo "$EMAIL" | sed 's/"/\\"/g' | tr -d '\n')",
        "first_name": "$(echo "$FIRST_NAME" | sed 's/"/\\"/g' | tr -d '\n')",
        "last_name": "$(echo "$LAST_NAME" | sed 's/"/\\"/g' | tr -d '\n')",
        "display_name": "$(echo "$DISPLAY_NAME" | sed 's/"/\\"/g' | tr -d '\n')",
        "role": "$(echo "$USER_ROLE" | sed 's/"/\\"/g' | tr -d '\n')"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/create_user_result.json 2>/dev/null || sudo rm -f /tmp/create_user_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_user_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_user_result.json
chmod 666 /tmp/create_user_result.json 2>/dev/null || sudo chmod 666 /tmp/create_user_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/create_user_result.json"
cat /tmp/create_user_result.json
echo ""
echo "=== Export complete ==="
