#!/bin/bash
# Export script for Create Customer task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Create Customer Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current partner count
CURRENT_COUNT=$(odoo_query "SELECT COUNT(*) FROM res_partner" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_partner_count 2>/dev/null || echo "0")

echo "Partner count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent partners to see what's actually in the database
echo ""
echo "=== DEBUG: Most recent partners in database ==="
odoo_query "SELECT id, name, email, phone, city, is_company FROM res_partner ORDER BY id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check if the target customer was added using CASE-INSENSITIVE matching
# Use LOWER() for case-insensitive comparison and TRIM() for whitespace
# Note: Odoo 17 doesn't have customer_rank column, using is_company instead
echo "Checking for customer 'Acme Corporation' (case-insensitive)..."
CUSTOMER_DATA=$(odoo_query "SELECT id, name, email, phone, city, is_company FROM res_partner WHERE LOWER(TRIM(name))='acme corporation' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# If not found with exact name, try partial match
if [ -z "$CUSTOMER_DATA" ]; then
    echo "Exact match not found, trying partial match..."
    CUSTOMER_DATA=$(odoo_query "SELECT id, name, email, phone, city, is_company FROM res_partner WHERE LOWER(name) LIKE '%acme%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# If still not found, check if any new partner was added (id > initial count)
if [ -z "$CUSTOMER_DATA" ]; then
    echo "Partial match not found, checking for any new partner..."
    CUSTOMER_DATA=$(odoo_query "SELECT id, name, email, phone, city, is_company FROM res_partner WHERE id > $INITIAL_COUNT ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$CUSTOMER_DATA" ]; then
        echo "Found new partner (not matching expected name):"
        echo "$CUSTOMER_DATA"
    fi
fi

# Parse customer data if found
CUSTOMER_FOUND="false"
CUSTOMER_ID=""
CUSTOMER_NAME=""
CUSTOMER_EMAIL=""
CUSTOMER_PHONE=""
CUSTOMER_CITY=""
CUSTOMER_IS_COMPANY=""

if [ -n "$CUSTOMER_DATA" ]; then
    CUSTOMER_FOUND="true"
    # Parse pipe-separated values (psql -A uses | as default separator)
    CUSTOMER_ID=$(echo "$CUSTOMER_DATA" | cut -d'|' -f1)
    CUSTOMER_NAME=$(echo "$CUSTOMER_DATA" | cut -d'|' -f2)
    CUSTOMER_EMAIL=$(echo "$CUSTOMER_DATA" | cut -d'|' -f3)
    CUSTOMER_PHONE=$(echo "$CUSTOMER_DATA" | cut -d'|' -f4)
    CUSTOMER_CITY=$(echo "$CUSTOMER_DATA" | cut -d'|' -f5)
    CUSTOMER_IS_COMPANY=$(echo "$CUSTOMER_DATA" | cut -d'|' -f6)
    echo "Customer found: ID=$CUSTOMER_ID, Name='$CUSTOMER_NAME', Email='$CUSTOMER_EMAIL', Phone='$CUSTOMER_PHONE', City='$CUSTOMER_CITY', IsCompany=$CUSTOMER_IS_COMPANY"
else
    echo "Customer 'Acme Corporation' NOT found in database"
fi

# Convert boolean values
if [ "$CUSTOMER_IS_COMPANY" = "t" ]; then
    CUSTOMER_IS_COMPANY_JSON="true"
else
    CUSTOMER_IS_COMPANY_JSON="false"
fi

# Escape any special characters in customer data for JSON
# Replace double quotes with escaped quotes
CUSTOMER_NAME_ESCAPED=$(echo "$CUSTOMER_NAME" | sed 's/"/\\"/g')
CUSTOMER_EMAIL_ESCAPED=$(echo "$CUSTOMER_EMAIL" | sed 's/"/\\"/g')
CUSTOMER_PHONE_ESCAPED=$(echo "$CUSTOMER_PHONE" | sed 's/"/\\"/g')
CUSTOMER_CITY_ESCAPED=$(echo "$CUSTOMER_CITY" | sed 's/"/\\"/g')

# Create JSON in a temp file first, then move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/create_customer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_partner_count": ${INITIAL_COUNT:-0},
    "current_partner_count": ${CURRENT_COUNT:-0},
    "customer_found": $CUSTOMER_FOUND,
    "customer": {
        "id": "$CUSTOMER_ID",
        "name": "$CUSTOMER_NAME_ESCAPED",
        "email": "$CUSTOMER_EMAIL_ESCAPED",
        "phone": "$CUSTOMER_PHONE_ESCAPED",
        "city": "$CUSTOMER_CITY_ESCAPED",
        "is_company": $CUSTOMER_IS_COMPANY_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location (handles permission issues)
# Remove old file first if possible, then copy (mv across filesystems may fail)
rm -f /tmp/create_customer_result.json 2>/dev/null || sudo rm -f /tmp/create_customer_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_customer_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_customer_result.json
chmod 666 /tmp/create_customer_result.json 2>/dev/null || sudo chmod 666 /tmp/create_customer_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_customer_result.json"
cat /tmp/create_customer_result.json

echo ""
echo "=== Export Complete ==="
