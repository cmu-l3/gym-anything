#!/bin/bash
set -e
echo "=== Exporting task results: add_specialist_addressbook ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_addressbook_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# Database Verification
# ==============================================================================

echo "Querying database for results..."

# 1. Get current total count
CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM addressbook" 2>/dev/null || echo "0")

# 2. Search for the specific entry
# We select all relevant columns to verify content accuracy
# Note: Organization column name might vary, so we try to check commonly used ones or just map what we find
ENTRY_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT JSON_OBJECT(
    'lastname', lastname,
    'firstname', firstname,
    'displayname', displayname,
    'specialty', specialty,
    'npi', npi,
    'street_address1', street_address1,
    'city', city,
    'state', state,
    'zip', zip,
    'phone', phone,
    'fax', fax,
    'email', email,
    'organization', organization
   ) 
   FROM addressbook 
   WHERE lastname='Torres' AND firstname='Rebecca' 
   LIMIT 1;" 2>/dev/null || echo "")

# If JSON_OBJECT isn't available (older MySQL/MariaDB), fallback to raw fields
if [ -z "$ENTRY_JSON" ]; then
    # Simple fallback: Check existence and dump fields to text, python will have to be robust
    # But NOSH docker usually has modern MariaDB. 
    # Let's try a CSV export if JSON fails or just manual construction
    RAW_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
      "SELECT lastname, firstname, specialty, npi, city, state, phone FROM addressbook WHERE lastname='Torres' AND firstname='Rebecca' LIMIT 1" 2>/dev/null || echo "")
    
    if [ -n "$RAW_DATA" ]; then
         # Manually construct minimal JSON if the DB query found something
         ENTRY_JSON="{\"found_raw\": \"$RAW_DATA\"}"
    else
         ENTRY_JSON="null"
    fi
fi

# ==============================================================================
# Generate Result JSON
# ==============================================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "entry_found": $(if [ -n "$ENTRY_JSON" ] && [ "$ENTRY_JSON" != "null" ]; then echo "true"; else echo "false"; fi),
    "entry_data": ${ENTRY_JSON:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="