#!/bin/bash
# Export script for Onboard Shop Manager task

echo "=== Exporting Onboard Shop Manager Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if user exists
USER_EXISTS="false"
USER_DATA=""
USER_ID=""
USER_LOGIN=""
USER_EMAIL=""
USER_FIRST=""
USER_LAST=""
USER_ROLES=""
PASSWORD_VALID="false"

# Try to get user data via WP-CLI (more reliable for roles)
if wp user get morgan_ops --field=ID --allow-root > /dev/null 2>&1; then
    USER_EXISTS="true"
    USER_ID=$(wp user get morgan_ops --field=ID --allow-root)
    USER_LOGIN=$(wp user get morgan_ops --field=user_login --allow-root)
    USER_EMAIL=$(wp user get morgan_ops --field=user_email --allow-root)
    USER_FIRST=$(wp user get morgan_ops --field=first_name --allow-root)
    USER_LAST=$(wp user get morgan_ops --field=last_name --allow-root)
    USER_ROLES=$(wp user get morgan_ops --field=roles --allow-root)
    
    # 2. Verify password using WP-CLI check-password command
    if wp user check-password "morgan_ops" "SecureManager2025!" --allow-root > /dev/null 2>&1; then
        PASSWORD_VALID="true"
    fi
else
    # Fallback to SQL if WP-CLI fails or user has different login but correct email
    USER_ID=$(wc_query "SELECT ID FROM wp_users WHERE user_email='morgan.lee@example.com' LIMIT 1")
    
    if [ -n "$USER_ID" ]; then
        USER_EXISTS="true"
        USER_LOGIN=$(wc_query "SELECT user_login FROM wp_users WHERE ID=$USER_ID")
        USER_EMAIL=$(wc_query "SELECT user_email FROM wp_users WHERE ID=$USER_ID")
        USER_FIRST=$(get_customer_firstname "$USER_ID")
        USER_LAST=$(get_customer_lastname "$USER_ID")
        # Get raw serialized capabilities
        USER_ROLES=$(wc_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$USER_ID AND meta_key='wp_capabilities'")
        
        # We can't easily check password via SQL only (hashed), so set to false/unknown
        PASSWORD_VALID="unknown"
    fi
fi

echo "User Found: $USER_EXISTS"
echo "Roles: $USER_ROLES"
echo "Password Valid: $PASSWORD_VALID"

# Escape strings for JSON
USER_LOGIN_ESC=$(json_escape "$USER_LOGIN")
USER_EMAIL_ESC=$(json_escape "$USER_EMAIL")
USER_FIRST_ESC=$(json_escape "$USER_FIRST")
USER_LAST_ESC=$(json_escape "$USER_LAST")
USER_ROLES_ESC=$(json_escape "$USER_ROLES")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "user_exists": $USER_EXISTS,
    "user_data": {
        "id": "$USER_ID",
        "login": "$USER_LOGIN_ESC",
        "email": "$USER_EMAIL_ESC",
        "first_name": "$USER_FIRST_ESC",
        "last_name": "$USER_LAST_ESC",
        "roles": "$USER_ROLES_ESC"
    },
    "password_valid": "$PASSWORD_VALID",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="