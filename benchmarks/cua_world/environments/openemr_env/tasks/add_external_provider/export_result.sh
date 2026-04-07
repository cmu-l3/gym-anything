#!/bin/bash
# Export script for Add External Provider task

echo "=== Exporting Add External Provider Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Get initial counts
INITIAL_ADDR_COUNT=$(cat /tmp/initial_address_count.txt 2>/dev/null || echo "0")
INITIAL_USER_ABOOK=$(cat /tmp/initial_user_abook_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_ADDR_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM addresses" 2>/dev/null || echo "0")
CURRENT_USER_ABOOK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM users WHERE abook_type IS NOT NULL AND abook_type != ''" 2>/dev/null || echo "0")

echo "Address counts: initial=$INITIAL_ADDR_COUNT, current=$CURRENT_ADDR_COUNT"
echo "User abook counts: initial=$INITIAL_USER_ABOOK, current=$CURRENT_USER_ABOOK"

# Search for the new provider entry in multiple possible locations
echo ""
echo "=== Searching for new provider entry ==="

# Search in addresses table
echo "Checking addresses table..."
ADDR_RESULT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "
    SELECT id, line1, line2, city, state, zip, plus_four, country, phone, fax, name, organization
    FROM addresses 
    WHERE (LOWER(city) = 'springfield' AND LOWER(state) IN ('ma', 'massachusetts'))
       OR (line1 LIKE '%456%Medical%Center%')
       OR (phone LIKE '%413%555%7890%')
       OR (LOWER(name) LIKE '%mitchell%')
    ORDER BY id DESC LIMIT 1
" 2>/dev/null)

# Search in users table (alternative storage location)
echo "Checking users table..."
USER_RESULT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "
    SELECT id, username, fname, lname, mname, title, specialty, organization, street, city, state, zip, phone, fax, email, npi, abook_type
    FROM users 
    WHERE (LOWER(city) = 'springfield' AND LOWER(state) IN ('ma', 'massachusetts') AND abook_type IS NOT NULL)
       OR (LOWER(lname) LIKE '%mitchell%' AND abook_type IS NOT NULL)
       OR (phone LIKE '%413%555%7890%')
       OR (npi = '1234567893')
    ORDER BY id DESC LIMIT 1
" 2>/dev/null)

# Debug output
echo ""
echo "=== DEBUG: Raw query results ==="
echo "Addresses result: $ADDR_RESULT"
echo "Users result: $USER_RESULT"
echo ""

# Parse results and determine which table has the entry
ENTRY_FOUND="false"
ENTRY_SOURCE=""
ENTRY_ID=""
ENTRY_NAME=""
ENTRY_CITY=""
ENTRY_STATE=""
ENTRY_ZIP=""
ENTRY_PHONE=""
ENTRY_FAX=""
ENTRY_STREET=""
ENTRY_ORG=""
ENTRY_SPECIALTY=""
ENTRY_NPI=""
ENTRY_EMAIL=""

# First check users table (more common for address book in recent OpenEMR)
if [ -n "$USER_RESULT" ]; then
    ENTRY_FOUND="true"
    ENTRY_SOURCE="users"
    
    # Parse tab-separated values from users table
    ENTRY_ID=$(echo "$USER_RESULT" | cut -f1)
    ENTRY_FNAME=$(echo "$USER_RESULT" | cut -f3)
    ENTRY_LNAME=$(echo "$USER_RESULT" | cut -f4)
    ENTRY_NAME="$ENTRY_FNAME $ENTRY_LNAME"
    ENTRY_TITLE=$(echo "$USER_RESULT" | cut -f6)
    ENTRY_SPECIALTY=$(echo "$USER_RESULT" | cut -f7)
    ENTRY_ORG=$(echo "$USER_RESULT" | cut -f8)
    ENTRY_STREET=$(echo "$USER_RESULT" | cut -f9)
    ENTRY_CITY=$(echo "$USER_RESULT" | cut -f10)
    ENTRY_STATE=$(echo "$USER_RESULT" | cut -f11)
    ENTRY_ZIP=$(echo "$USER_RESULT" | cut -f12)
    ENTRY_PHONE=$(echo "$USER_RESULT" | cut -f13)
    ENTRY_FAX=$(echo "$USER_RESULT" | cut -f14)
    ENTRY_EMAIL=$(echo "$USER_RESULT" | cut -f15)
    ENTRY_NPI=$(echo "$USER_RESULT" | cut -f16)
    
    echo "Found entry in users table:"
    echo "  ID: $ENTRY_ID"
    echo "  Name: $ENTRY_NAME"
    echo "  City: $ENTRY_CITY, State: $ENTRY_STATE"
elif [ -n "$ADDR_RESULT" ]; then
    ENTRY_FOUND="true"
    ENTRY_SOURCE="addresses"
    
    # Parse tab-separated values from addresses table
    ENTRY_ID=$(echo "$ADDR_RESULT" | cut -f1)
    ENTRY_STREET=$(echo "$ADDR_RESULT" | cut -f2)
    ENTRY_CITY=$(echo "$ADDR_RESULT" | cut -f4)
    ENTRY_STATE=$(echo "$ADDR_RESULT" | cut -f5)
    ENTRY_ZIP=$(echo "$ADDR_RESULT" | cut -f6)
    ENTRY_PHONE=$(echo "$ADDR_RESULT" | cut -f9)
    ENTRY_FAX=$(echo "$ADDR_RESULT" | cut -f10)
    ENTRY_NAME=$(echo "$ADDR_RESULT" | cut -f11)
    ENTRY_ORG=$(echo "$ADDR_RESULT" | cut -f12)
    
    echo "Found entry in addresses table:"
    echo "  ID: $ENTRY_ID"
    echo "  Name: $ENTRY_NAME"
    echo "  City: $ENTRY_CITY, State: $ENTRY_STATE"
else
    echo "No matching entry found in either table"
fi

# Check if entry was newly created (count increased)
NEW_ENTRY_CREATED="false"
if [ "$CURRENT_ADDR_COUNT" -gt "$INITIAL_ADDR_COUNT" ] || [ "$CURRENT_USER_ABOOK" -gt "$INITIAL_USER_ABOOK" ]; then
    NEW_ENTRY_CREATED="true"
    echo "New entry detected (counts increased)"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' ' | sed 's/  */ /g'
}

ENTRY_NAME_ESC=$(escape_json "$ENTRY_NAME")
ENTRY_STREET_ESC=$(escape_json "$ENTRY_STREET")
ENTRY_ORG_ESC=$(escape_json "$ENTRY_ORG")
ENTRY_SPECIALTY_ESC=$(escape_json "$ENTRY_SPECIALTY")
ENTRY_EMAIL_ESC=$(escape_json "$ENTRY_EMAIL")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/add_provider_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_address_count": ${INITIAL_ADDR_COUNT:-0},
    "current_address_count": ${CURRENT_ADDR_COUNT:-0},
    "initial_user_abook_count": ${INITIAL_USER_ABOOK:-0},
    "current_user_abook_count": ${CURRENT_USER_ABOOK:-0},
    "entry_found": $ENTRY_FOUND,
    "new_entry_created": $NEW_ENTRY_CREATED,
    "entry_source": "$ENTRY_SOURCE",
    "entry": {
        "id": "$ENTRY_ID",
        "name": "$ENTRY_NAME_ESC",
        "street": "$ENTRY_STREET_ESC",
        "city": "$ENTRY_CITY",
        "state": "$ENTRY_STATE",
        "zip": "$ENTRY_ZIP",
        "phone": "$ENTRY_PHONE",
        "fax": "$ENTRY_FAX",
        "email": "$ENTRY_EMAIL_ESC",
        "organization": "$ENTRY_ORG_ESC",
        "specialty": "$ENTRY_SPECIALTY_ESC",
        "npi": "$ENTRY_NPI"
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/add_external_provider_result.json 2>/dev/null || sudo rm -f /tmp/add_external_provider_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_external_provider_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_external_provider_result.json
chmod 666 /tmp/add_external_provider_result.json 2>/dev/null || sudo chmod 666 /tmp/add_external_provider_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_external_provider_result.json"
cat /tmp/add_external_provider_result.json
echo ""
echo "=== Export Complete ==="