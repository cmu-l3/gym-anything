#!/bin/bash
# Export script for Provision Dashboard Widget Access task

echo "=== Exporting Provision Dashboard Widget Access Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 1. Check if user exists
USER_EXISTS="false"
USER_CHECK=$(matomo_query "SELECT login FROM matomo_user WHERE login='lobby_display'")
if [ "$USER_CHECK" = "lobby_display" ]; then
    USER_EXISTS="true"
fi

# 2. Check permissions (should have 'view' on site 1)
PERMISSION_LEVEL="none"
ACCESS_CHECK=$(matomo_query "SELECT access FROM matomo_access WHERE login='lobby_display' AND idsite=1")
if [ -n "$ACCESS_CHECK" ]; then
    PERMISSION_LEVEL="$ACCESS_CHECK"
fi

# 3. Check Super User status (should be 0)
IS_SUPERUSER="false"
SUPER_CHECK=$(matomo_query "SELECT superuser_access FROM matomo_user WHERE login='lobby_display'")
if [ "$SUPER_CHECK" = "1" ]; then
    IS_SUPERUSER="true"
fi

# 4. Check Output File and Token
FILE_EXISTS="false"
FILE_PATH="/home/ga/lobby_widget.html"
EXTRACTED_TOKEN=""
WIDGET_IFRAME_FOUND="false"
TOKEN_FUNCTIONAL="false"
TOKEN_USER="unknown"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    CONTENT=$(cat "$FILE_PATH")
    
    # Check for iframe
    if echo "$CONTENT" | grep -q "<iframe"; then
        WIDGET_IFRAME_FOUND="true"
    fi

    # Extract token_auth (simple regex look)
    # Looking for &token_auth=([a-f0-9]+)
    EXTRACTED_TOKEN=$(echo "$CONTENT" | grep -o "token_auth=[a-f0-9]*" | cut -d'=' -f2 | head -1)
    
    if [ -n "$EXTRACTED_TOKEN" ]; then
        echo "Found token in file: ${EXTRACTED_TOKEN:0:5}..."
        
        # 5. Verify Token Functionality and Ownership via API
        # We use the token to ask "Who am I?"
        # API method: UsersManager.getUser (requires at least view access to check self?) 
        # Better: API.getSettings or similar.
        # Simplest: UsersManager.getUser with user_login=lobby_display (needs view access)
        # OR: Just check SitesManager.getSitesIdFromSiteUrl which requires view access
        
        # Let's try to get the user associated with the token
        # There isn't a direct "whoami" API, but we can verify if the token works for the specific user
        
        # Test 1: Can we access data?
        API_RESPONSE=$(curl -s "http://localhost/index.php?module=API&method=SitesManager.getSiteFromId&idSite=1&format=JSON&token_auth=$EXTRACTED_TOKEN")
        
        # Check if response contains the site name "Initial Site" (indicates success)
        if echo "$API_RESPONSE" | grep -q "Initial Site"; then
            TOKEN_FUNCTIONAL="true"
        fi
        
        # Test 2: Identify the user (Indirectly)
        # We can check if this token allows Admin actions (it shouldn't)
        # API: UsersManager.getUsers (Admin only)
        ADMIN_TEST=$(curl -s "http://localhost/index.php?module=API&method=UsersManager.getUsers&format=JSON&token_auth=$EXTRACTED_TOKEN")
        
        if echo "$ADMIN_TEST" | grep -q "error"; then
            # Good, it returned an error (likely "You must be logged in..." or "Access denied")
            # Wait, if token is valid but restricted, it should deny admin actions.
            # Matomo returns specific error messages.
            echo "Admin test result: restricted (good)"
        else
            # If it returns a list of users, this is an Admin token!
            if echo "$ADMIN_TEST" | grep -q "lobby_display"; then
                TOKEN_USER="admin_or_superuser"
            fi
        fi
        
        # Refined Ownership Check:
        # Since Matomo 4 hashes tokens, we can't look it up in DB.
        # But we verified 'lobby_display' exists and is NOT a superuser.
        # If the token works for site 1 (which lobby_display has access to)
        # AND the token does NOT work for admin actions
        # AND we extracted it from the file created by the agent...
        # We can infer correct behavior.
        
        # Ideally, we want to know EXACTLY who the token belongs to.
        # We can try to fetch the user's own profile? 
        # API: UsersManager.getUser (requires param user_login)
        # If I call UsersManager.getUser&user_login=lobby_display with the token:
        # - If token is lobby_display: Success
        # - If token is admin: Success (ambiguous)
        # - If token is unrelated: Failure
        
        USER_SELF_TEST=$(curl -s "http://localhost/index.php?module=API&method=UsersManager.getUser&user_login=lobby_display&format=JSON&token_auth=$EXTRACTED_TOKEN")
        
        if echo "$USER_SELF_TEST" | grep -q "lobby_display"; then
            # Token allows viewing lobby_display profile.
            # Combined with IS_SUPERUSER check from DB, we can be confident.
            TOKEN_USER="lobby_display" 
            if [ "$IS_SUPERUSER" = "true" ]; then
                TOKEN_USER="lobby_display (but is superuser)"
            fi
            
            # Double check it's not admin by checking another user
            OTHER_USER_TEST=$(curl -s "http://localhost/index.php?module=API&method=UsersManager.getUser&user_login=admin&format=JSON&token_auth=$EXTRACTED_TOKEN")
            if echo "$OTHER_USER_TEST" | grep -q "admin"; then
                 TOKEN_USER="superuser_token" # It can see admin's profile too
            fi
        else
            TOKEN_USER="invalid_or_wrong_user"
        fi
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/provision_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "user_exists": $USER_EXISTS,
    "permission_level": "$PERMISSION_LEVEL",
    "is_superuser": $IS_SUPERUSER,
    "file_exists": $FILE_EXISTS,
    "widget_iframe_found": $WIDGET_IFRAME_FOUND,
    "token_extracted": "$(echo "$EXTRACTED_TOKEN" | sed 's/"//g')", 
    "token_functional": $TOKEN_FUNCTIONAL,
    "token_user_determination": "$TOKEN_USER",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/provision_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/provision_result.json
chmod 666 /tmp/provision_result.json
rm -f "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/provision_result.json