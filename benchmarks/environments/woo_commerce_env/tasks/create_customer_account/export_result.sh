#!/bin/bash
# Export script for Create Customer Account task

echo "=== Exporting Create Customer Account Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity before proceeding
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "customer_found": false, "customer": {}}' > /tmp/create_customer_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current customer count
CURRENT_COUNT=$(get_customer_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_customer_count 2>/dev/null || echo "0")

echo "Customer count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent users
echo ""
echo "=== DEBUG: Most recent users in database ==="
wc_query_headers "SELECT u.ID, u.user_login, u.user_email, u.display_name, u.user_registered
    FROM wp_users u
    ORDER BY u.ID DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target customer by email
echo "Checking for customer 'sarah.johnson@example.com' (case-insensitive)..."
CUSTOMER_DATA=$(get_customer_by_email "sarah.johnson@example.com" 2>/dev/null)

# If not found by email, try by name
if [ -z "$CUSTOMER_DATA" ]; then
    echo "Email match not found, trying by name..."
    CUSTOMER_DATA=$(get_customer_by_name "Sarah" "Johnson" 2>/dev/null)
fi

# If not found by name, try by username
if [ -z "$CUSTOMER_DATA" ]; then
    echo "Name match not found, trying by username..."
    CUSTOMER_DATA=$(wc_query "SELECT u.ID, u.user_email, u.user_login, u.display_name, u.user_registered
        FROM wp_users u
        WHERE LOWER(TRIM(u.user_login)) = 'sarahjohnson'
        LIMIT 1" 2>/dev/null)
fi

# NOTE: No "newest entity" fallback - if the specific customer is not found,
# it's reported as not found. The verifier handles this appropriately.

# Parse customer data
CUSTOMER_FOUND="false"
CUSTOMER_ID=""
CUSTOMER_EMAIL=""
CUSTOMER_USERNAME=""
CUSTOMER_DISPLAYNAME=""
CUSTOMER_REGISTERED=""
CUSTOMER_FIRSTNAME=""
CUSTOMER_LASTNAME=""
CUSTOMER_ROLE=""

if [ -n "$CUSTOMER_DATA" ]; then
    CUSTOMER_FOUND="true"
    CUSTOMER_ID=$(echo "$CUSTOMER_DATA" | cut -f1)
    CUSTOMER_EMAIL=$(echo "$CUSTOMER_DATA" | cut -f2)
    CUSTOMER_USERNAME=$(echo "$CUSTOMER_DATA" | cut -f3)
    CUSTOMER_DISPLAYNAME=$(echo "$CUSTOMER_DATA" | cut -f4)
    CUSTOMER_REGISTERED=$(echo "$CUSTOMER_DATA" | cut -f5)

    # Get first name, last name, and role from usermeta
    CUSTOMER_FIRSTNAME=$(get_customer_firstname "$CUSTOMER_ID" 2>/dev/null)
    CUSTOMER_LASTNAME=$(get_customer_lastname "$CUSTOMER_ID" 2>/dev/null)
    CUSTOMER_ROLE=$(get_customer_role "$CUSTOMER_ID" 2>/dev/null)

    echo "Customer found: ID=$CUSTOMER_ID, Email='$CUSTOMER_EMAIL', Username='$CUSTOMER_USERNAME', Name='$CUSTOMER_FIRSTNAME $CUSTOMER_LASTNAME', Role='$CUSTOMER_ROLE'"
else
    echo "Customer 'sarah.johnson@example.com' NOT found in database"
fi

# Escape special characters for JSON (handles quotes, backslashes, newlines, etc.)
CUSTOMER_EMAIL_ESC=$(json_escape "$CUSTOMER_EMAIL")
CUSTOMER_USERNAME_ESC=$(json_escape "$CUSTOMER_USERNAME")
CUSTOMER_DISPLAYNAME_ESC=$(json_escape "$CUSTOMER_DISPLAYNAME")
CUSTOMER_FIRSTNAME_ESC=$(json_escape "$CUSTOMER_FIRSTNAME")
CUSTOMER_LASTNAME_ESC=$(json_escape "$CUSTOMER_LASTNAME")
CUSTOMER_ROLE_ESC=$(json_escape "$CUSTOMER_ROLE")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/create_customer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_customer_count": ${INITIAL_COUNT:-0},
    "current_customer_count": ${CURRENT_COUNT:-0},
    "customer_found": $CUSTOMER_FOUND,
    "customer": {
        "id": "$CUSTOMER_ID",
        "email": "$CUSTOMER_EMAIL_ESC",
        "username": "$CUSTOMER_USERNAME_ESC",
        "display_name": "$CUSTOMER_DISPLAYNAME_ESC",
        "first_name": "$CUSTOMER_FIRSTNAME_ESC",
        "last_name": "$CUSTOMER_LASTNAME_ESC",
        "role_capabilities": "$CUSTOMER_ROLE_ESC",
        "registered": "$CUSTOMER_REGISTERED"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_customer_result.json

echo ""
cat /tmp/create_customer_result.json
echo ""
echo "=== Export Complete ==="
