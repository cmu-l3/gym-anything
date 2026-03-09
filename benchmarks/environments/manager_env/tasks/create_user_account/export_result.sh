#!/bin/bash
set -e

echo "=== Exporting create_user_account results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

COOKIE_FILE="/tmp/mgr_export_cookies.txt"
MANAGER_URL="http://localhost:8080"

# ---------------------------------------------------------------------------
# Check 1: User Existence (via Administrator view)
# ---------------------------------------------------------------------------
echo "Checking for user existence..."
rm -f "$COOKIE_FILE"

# Login as administrator
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null 2>/dev/null

USERS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/users" -L 2>/dev/null || echo "")

USER_EXISTS="false"
if echo "$USERS_PAGE" | grep -qi "sjohnson"; then
    USER_EXISTS="true"
fi

# Check for partial matches (common mistakes)
PARTIAL_MATCH="false"
if [ "$USER_EXISTS" = "false" ]; then
    if echo "$USERS_PAGE" | grep -qi "sarah\|johnson"; then
        PARTIAL_MATCH="true"
    fi
fi

# Get current user count
CURRENT_USER_COUNT=$(echo "$USERS_PAGE" | grep -c "user-form" 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------------------
# Check 2: Authentication Test (Can we log in as sjohnson?)
# ---------------------------------------------------------------------------
echo "Testing authentication..."
rm -f "$COOKIE_FILE" # Clear admin cookies

# Attempt login with new credentials
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=sjohnson&Password=Northwind2024!" \
    -L -w "\nHTTP_CODE:%{http_code}" 2>/dev/null)

LOGIN_HTTP=$(echo "$LOGIN_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | sed 's/HTTP_CODE:.*//')

AUTH_SUCCESS="false"
# Success if we are redirected to businesses page or see the business list
if echo "$LOGIN_BODY" | grep -qi "Northwind\|Businesses\|start\?"; then
    AUTH_SUCCESS="true"
elif [ "$LOGIN_HTTP" = "200" ] && ! echo "$LOGIN_BODY" | grep -qi "login\|sign.in"; then
    # Sometimes it lands on a page without explicit "Businesses" text but is logged in
    AUTH_SUCCESS="true"
fi

# ---------------------------------------------------------------------------
# Check 3: Business Access (Does sjohnson see Northwind?)
# ---------------------------------------------------------------------------
BUSINESS_ACCESS="false"

if [ "$AUTH_SUCCESS" = "true" ]; then
    # We are logged in as sjohnson. Check visible businesses.
    # Note: If user has access to only one business, Manager often redirects straight to it.
    
    # Check current page content from login redirect
    if echo "$LOGIN_BODY" | grep -qi "Northwind Traders"; then
        BUSINESS_ACCESS="true"
    else
        # Explicitly fetch business list if not currently there
        BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            "$MANAGER_URL/businesses" -L 2>/dev/null || echo "")
        
        if echo "$BIZ_PAGE" | grep -qi "Northwind Traders"; then
            BUSINESS_ACCESS="true"
        elif echo "$BIZ_PAGE" | grep -qi "Northwind"; then
            # Maybe partial name match
            BUSINESS_ACCESS="true"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Final Screenshot
# ---------------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Export JSON
# ---------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_exists": $USER_EXISTS,
    "partial_name_match": $PARTIAL_MATCH,
    "initial_user_count": $INITIAL_USER_COUNT,
    "current_user_count": $CURRENT_USER_COUNT,
    "auth_success": $AUTH_SUCCESS,
    "business_access": $BUSINESS_ACCESS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="