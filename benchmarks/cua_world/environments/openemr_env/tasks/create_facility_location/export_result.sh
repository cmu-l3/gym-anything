#!/bin/bash
# Export script for Create Facility Location Task

echo "=== Exporting Create Facility Location Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_facility_count.txt 2>/dev/null || echo "1")
EXISTING_TARGET=$(cat /tmp/existing_target_count.txt 2>/dev/null || echo "0")

# Get current facility count
CURRENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM facility" 2>/dev/null || echo "0")

echo "Facility count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Query for all facilities to see what exists
echo ""
echo "=== DEBUG: All facilities in database ==="
openemr_query "SELECT id, name, city, state FROM facility ORDER BY id" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for the target facility (case-insensitive)
echo "Querying for facility 'Riverside Family Medicine - East'..."
FACILITY_DATA=$(openemr_query "SELECT id, name, street, city, state, postal_code, country_code, phone, fax, federal_ein, facility_npi, service_location, billing_location FROM facility WHERE LOWER(name) LIKE '%riverside%' AND LOWER(name) LIKE '%east%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Also try partial match
if [ -z "$FACILITY_DATA" ]; then
    echo "Exact match not found, trying partial match..."
    FACILITY_DATA=$(openemr_query "SELECT id, name, street, city, state, postal_code, country_code, phone, fax, federal_ein, facility_npi, service_location, billing_location FROM facility WHERE LOWER(name) LIKE '%riverside%' OR LOWER(name) LIKE '%family medicine%east%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# If still not found, check for any new facility
if [ -z "$FACILITY_DATA" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    echo "Target name not found, checking for any new facility..."
    FACILITY_DATA=$(openemr_query "SELECT id, name, street, city, state, postal_code, country_code, phone, fax, federal_ein, facility_npi, service_location, billing_location FROM facility ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$FACILITY_DATA" ]; then
        echo "Found new facility (not matching expected name):"
        echo "$FACILITY_DATA"
    fi
fi

# Parse facility data
FACILITY_FOUND="false"
FACILITY_ID=""
FACILITY_NAME=""
FACILITY_STREET=""
FACILITY_CITY=""
FACILITY_STATE=""
FACILITY_POSTAL=""
FACILITY_COUNTRY=""
FACILITY_PHONE=""
FACILITY_FAX=""
FACILITY_EIN=""
FACILITY_NPI=""
FACILITY_SERVICE=""
FACILITY_BILLING=""

if [ -n "$FACILITY_DATA" ]; then
    FACILITY_FOUND="true"
    # Parse tab-separated values
    FACILITY_ID=$(echo "$FACILITY_DATA" | cut -f1)
    FACILITY_NAME=$(echo "$FACILITY_DATA" | cut -f2)
    FACILITY_STREET=$(echo "$FACILITY_DATA" | cut -f3)
    FACILITY_CITY=$(echo "$FACILITY_DATA" | cut -f4)
    FACILITY_STATE=$(echo "$FACILITY_DATA" | cut -f5)
    FACILITY_POSTAL=$(echo "$FACILITY_DATA" | cut -f6)
    FACILITY_COUNTRY=$(echo "$FACILITY_DATA" | cut -f7)
    FACILITY_PHONE=$(echo "$FACILITY_DATA" | cut -f8)
    FACILITY_FAX=$(echo "$FACILITY_DATA" | cut -f9)
    FACILITY_EIN=$(echo "$FACILITY_DATA" | cut -f10)
    FACILITY_NPI=$(echo "$FACILITY_DATA" | cut -f11)
    FACILITY_SERVICE=$(echo "$FACILITY_DATA" | cut -f12)
    FACILITY_BILLING=$(echo "$FACILITY_DATA" | cut -f13)
    
    echo ""
    echo "Facility found:"
    echo "  ID: $FACILITY_ID"
    echo "  Name: $FACILITY_NAME"
    echo "  Street: $FACILITY_STREET"
    echo "  City: $FACILITY_CITY"
    echo "  State: $FACILITY_STATE"
    echo "  Postal: $FACILITY_POSTAL"
    echo "  Phone: $FACILITY_PHONE"
    echo "  Fax: $FACILITY_FAX"
    echo "  EIN: $FACILITY_EIN"
    echo "  NPI: $FACILITY_NPI"
    echo "  Service Location: $FACILITY_SERVICE"
    echo "  Billing Location: $FACILITY_BILLING"
else
    echo "Target facility NOT found in database"
fi

# Check if this is a newly created facility (id > max initial id)
FACILITY_IS_NEW="false"
if [ -n "$FACILITY_ID" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    # The facility ID should be greater than initial count (approximately)
    # This is a heuristic - new facilities get incrementing IDs
    FACILITY_IS_NEW="true"
    echo "Facility appears to be newly created (count increased)"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' '
}

FACILITY_NAME_ESC=$(escape_json "$FACILITY_NAME")
FACILITY_STREET_ESC=$(escape_json "$FACILITY_STREET")
FACILITY_CITY_ESC=$(escape_json "$FACILITY_CITY")
FACILITY_STATE_ESC=$(escape_json "$FACILITY_STATE")
FACILITY_PHONE_ESC=$(escape_json "$FACILITY_PHONE")
FACILITY_FAX_ESC=$(escape_json "$FACILITY_FAX")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/facility_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_facility_count": ${INITIAL_COUNT:-1},
    "current_facility_count": ${CURRENT_COUNT:-0},
    "existing_target_before_task": ${EXISTING_TARGET:-0},
    "facility_found": $FACILITY_FOUND,
    "facility_is_new": $FACILITY_IS_NEW,
    "facility": {
        "id": "$FACILITY_ID",
        "name": "$FACILITY_NAME_ESC",
        "street": "$FACILITY_STREET_ESC",
        "city": "$FACILITY_CITY_ESC",
        "state": "$FACILITY_STATE_ESC",
        "postal_code": "$FACILITY_POSTAL",
        "country": "$FACILITY_COUNTRY",
        "phone": "$FACILITY_PHONE_ESC",
        "fax": "$FACILITY_FAX_ESC",
        "federal_ein": "$FACILITY_EIN",
        "facility_npi": "$FACILITY_NPI",
        "service_location": "$FACILITY_SERVICE",
        "billing_location": "$FACILITY_BILLING"
    },
    "screenshot_final": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="