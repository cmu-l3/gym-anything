#!/bin/bash
# Export script for Create Customer task

echo "=== Exporting Create Customer Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current customer count
CURRENT_COUNT=$(get_customer_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_customer_count 2>/dev/null || echo "0")

echo "Customer count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent customers
echo ""
echo "=== DEBUG: Most recent customers in database ==="
magento_query_headers "SELECT entity_id, email, firstname, lastname, group_id FROM customer_entity ORDER BY entity_id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target customer by email (case-insensitive)
echo "Checking for customer 'sarah.johnson@example.com' (case-insensitive)..."
CUSTOMER_DATA=$(get_customer_by_email "sarah.johnson@example.com" 2>/dev/null)

# No fallback logic - we only accept the exact expected email
if [ -z "$CUSTOMER_DATA" ]; then
    echo "Customer 'sarah.johnson@example.com' NOT found in database"
fi

# Parse customer data
CUSTOMER_FOUND="false"
CUSTOMER_ID=""
CUSTOMER_EMAIL=""
CUSTOMER_FIRSTNAME=""
CUSTOMER_LASTNAME=""
CUSTOMER_GROUP_ID=""
CUSTOMER_GROUP_NAME=""
CUSTOMER_CREATED=""

if [ -n "$CUSTOMER_DATA" ]; then
    CUSTOMER_FOUND="true"
    CUSTOMER_ID=$(echo "$CUSTOMER_DATA" | cut -f1)
    CUSTOMER_EMAIL=$(echo "$CUSTOMER_DATA" | cut -f2)
    CUSTOMER_FIRSTNAME=$(echo "$CUSTOMER_DATA" | cut -f3)
    CUSTOMER_LASTNAME=$(echo "$CUSTOMER_DATA" | cut -f4)
    CUSTOMER_GROUP_ID=$(echo "$CUSTOMER_DATA" | cut -f5)
    CUSTOMER_CREATED=$(echo "$CUSTOMER_DATA" | cut -f6)

    # Get group name
    CUSTOMER_GROUP_NAME=$(magento_query "SELECT customer_group_code FROM customer_group WHERE customer_group_id=$CUSTOMER_GROUP_ID" 2>/dev/null)

    echo "Customer found: ID=$CUSTOMER_ID, Email='$CUSTOMER_EMAIL', Name='$CUSTOMER_FIRSTNAME $CUSTOMER_LASTNAME', Group='$CUSTOMER_GROUP_NAME'"
else
    echo "Customer 'sarah.johnson@example.com' NOT found in database"
fi

# Escape special characters for JSON
CUSTOMER_FIRSTNAME_ESC=$(echo "$CUSTOMER_FIRSTNAME" | sed 's/"/\\"/g')
CUSTOMER_LASTNAME_ESC=$(echo "$CUSTOMER_LASTNAME" | sed 's/"/\\"/g')
CUSTOMER_EMAIL_ESC=$(echo "$CUSTOMER_EMAIL" | sed 's/"/\\"/g')
CUSTOMER_GROUP_NAME_ESC=$(echo "$CUSTOMER_GROUP_NAME" | sed 's/"/\\"/g')

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
        "firstname": "$CUSTOMER_FIRSTNAME_ESC",
        "lastname": "$CUSTOMER_LASTNAME_ESC",
        "group_id": "$CUSTOMER_GROUP_ID",
        "group_name": "$CUSTOMER_GROUP_NAME_ESC",
        "created_at": "$CUSTOMER_CREATED"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_customer_result.json

echo ""
cat /tmp/create_customer_result.json
echo ""
echo "=== Export Complete ==="
