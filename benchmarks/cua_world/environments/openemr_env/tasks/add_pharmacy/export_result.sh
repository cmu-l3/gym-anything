#!/bin/bash
# Export script for Add Pharmacy task
# Queries database and exports verification data to JSON

echo "=== Exporting Add Pharmacy Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    echo "Final screenshot captured"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial and current pharmacy counts
INITIAL_COUNT=$(cat /tmp/initial_pharmacy_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM pharmacies" 2>/dev/null || echo "0")

echo "Pharmacy count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show all pharmacies to see what's in the database
echo ""
echo "=== DEBUG: All pharmacies in database ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "SELECT id, name, address_line_1, city, state, zip, phone, fax FROM pharmacies ORDER BY id DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Search for the target pharmacy with multiple matching strategies
echo "Searching for CVS Pharmacy #8472..."

# Strategy 1: Match by name containing CVS and 8472
PHARMACY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT id, name, address_line_1, city, state, zip, phone, fax, email, npi FROM pharmacies WHERE name LIKE '%CVS%' AND name LIKE '%8472%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Strategy 2: Match by address in Boston if name match fails
if [ -z "$PHARMACY_DATA" ]; then
    echo "Name match not found, trying address match..."
    PHARMACY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT id, name, address_line_1, city, state, zip, phone, fax, email, npi FROM pharmacies WHERE address_line_1 LIKE '%2150%' AND address_line_1 LIKE '%Commonwealth%' AND city='Boston' ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Strategy 3: If still not found, check if any new pharmacy was added
if [ -z "$PHARMACY_DATA" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    echo "No specific match found, checking for any new pharmacy..."
    PHARMACY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT id, name, address_line_1, city, state, zip, phone, fax, email, npi FROM pharmacies ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Found newest pharmacy (may not match expected):"
    echo "$PHARMACY_DATA"
fi

# Parse pharmacy data
PHARMACY_FOUND="false"
PHARMACY_ID=""
PHARMACY_NAME=""
PHARMACY_ADDRESS=""
PHARMACY_CITY=""
PHARMACY_STATE=""
PHARMACY_ZIP=""
PHARMACY_PHONE=""
PHARMACY_FAX=""
PHARMACY_EMAIL=""
PHARMACY_NPI=""

if [ -n "$PHARMACY_DATA" ]; then
    PHARMACY_FOUND="true"
    PHARMACY_ID=$(echo "$PHARMACY_DATA" | cut -f1)
    PHARMACY_NAME=$(echo "$PHARMACY_DATA" | cut -f2)
    PHARMACY_ADDRESS=$(echo "$PHARMACY_DATA" | cut -f3)
    PHARMACY_CITY=$(echo "$PHARMACY_DATA" | cut -f4)
    PHARMACY_STATE=$(echo "$PHARMACY_DATA" | cut -f5)
    PHARMACY_ZIP=$(echo "$PHARMACY_DATA" | cut -f6)
    PHARMACY_PHONE=$(echo "$PHARMACY_DATA" | cut -f7)
    PHARMACY_FAX=$(echo "$PHARMACY_DATA" | cut -f8)
    PHARMACY_EMAIL=$(echo "$PHARMACY_DATA" | cut -f9)
    PHARMACY_NPI=$(echo "$PHARMACY_DATA" | cut -f10)
    
    echo ""
    echo "Pharmacy found:"
    echo "  ID: $PHARMACY_ID"
    echo "  Name: $PHARMACY_NAME"
    echo "  Address: $PHARMACY_ADDRESS"
    echo "  City: $PHARMACY_CITY"
    echo "  State: $PHARMACY_STATE"
    echo "  Zip: $PHARMACY_ZIP"
    echo "  Phone: $PHARMACY_PHONE"
    echo "  Fax: $PHARMACY_FAX"
    echo "  Email: $PHARMACY_EMAIL"
    echo "  NPI: $PHARMACY_NPI"
else
    echo "No matching pharmacy found in database"
fi

# Validate fields
NAME_HAS_CVS="false"
NAME_HAS_8472="false"
ADDRESS_MATCHES="false"
CITY_MATCHES="false"
STATE_MATCHES="false"
ZIP_MATCHES="false"
PHONE_PRESENT="false"
FAX_PRESENT="false"

if [ -n "$PHARMACY_NAME" ]; then
    NAME_LOWER=$(echo "$PHARMACY_NAME" | tr '[:upper:]' '[:lower:]')
    if echo "$NAME_LOWER" | grep -q "cvs"; then
        NAME_HAS_CVS="true"
    fi
    if echo "$PHARMACY_NAME" | grep -q "8472"; then
        NAME_HAS_8472="true"
    fi
fi

if echo "$PHARMACY_ADDRESS" | grep -qi "2150.*commonwealth\|commonwealth.*2150"; then
    ADDRESS_MATCHES="true"
fi

if [ "$(echo "$PHARMACY_CITY" | tr '[:upper:]' '[:lower:]')" = "boston" ]; then
    CITY_MATCHES="true"
fi

if [ "$(echo "$PHARMACY_STATE" | tr '[:upper:]' '[:lower:]')" = "ma" ]; then
    STATE_MATCHES="true"
fi

if echo "$PHARMACY_ZIP" | grep -q "02135"; then
    ZIP_MATCHES="true"
fi

if [ -n "$PHARMACY_PHONE" ] && [ ${#PHARMACY_PHONE} -ge 10 ]; then
    PHONE_PRESENT="true"
fi

if [ -n "$PHARMACY_FAX" ] && [ ${#PHARMACY_FAX} -ge 10 ]; then
    FAX_PRESENT="true"
fi

# Determine if pharmacy was newly created
NEWLY_CREATED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    NEWLY_CREATED="true"
fi

# Escape special characters for JSON
PHARMACY_NAME_ESCAPED=$(echo "$PHARMACY_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
PHARMACY_ADDRESS_ESCAPED=$(echo "$PHARMACY_ADDRESS" | sed 's/"/\\"/g' | tr '\n' ' ')
PHARMACY_EMAIL_ESCAPED=$(echo "$PHARMACY_EMAIL" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/pharmacy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_timing": {
        "start_timestamp": $TASK_START,
        "end_timestamp": $TASK_END,
        "duration_seconds": $((TASK_END - TASK_START))
    },
    "pharmacy_counts": {
        "initial": $INITIAL_COUNT,
        "current": $CURRENT_COUNT,
        "newly_created": $NEWLY_CREATED
    },
    "pharmacy_found": $PHARMACY_FOUND,
    "pharmacy": {
        "id": "$PHARMACY_ID",
        "name": "$PHARMACY_NAME_ESCAPED",
        "address": "$PHARMACY_ADDRESS_ESCAPED",
        "city": "$PHARMACY_CITY",
        "state": "$PHARMACY_STATE",
        "zip": "$PHARMACY_ZIP",
        "phone": "$PHARMACY_PHONE",
        "fax": "$PHARMACY_FAX",
        "email": "$PHARMACY_EMAIL_ESCAPED",
        "npi": "$PHARMACY_NPI"
    },
    "validation": {
        "name_has_cvs": $NAME_HAS_CVS,
        "name_has_8472": $NAME_HAS_8472,
        "address_matches": $ADDRESS_MATCHES,
        "city_matches": $CITY_MATCHES,
        "state_matches": $STATE_MATCHES,
        "zip_matches": $ZIP_MATCHES,
        "phone_present": $PHONE_PRESENT,
        "fax_present": $FAX_PRESENT
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/add_pharmacy_result.json 2>/dev/null || sudo rm -f /tmp/add_pharmacy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_pharmacy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_pharmacy_result.json
chmod 666 /tmp/add_pharmacy_result.json 2>/dev/null || sudo chmod 666 /tmp/add_pharmacy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/add_pharmacy_result.json
echo ""
echo "=== Export Complete ==="