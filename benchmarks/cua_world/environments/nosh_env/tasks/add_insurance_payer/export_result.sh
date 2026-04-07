#!/bin/bash
echo "=== Exporting add_insurance_payer results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the database for the newly created record
# We look for 'Aetna Better Health' specifically
echo "Querying database..."
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT displayname, street_address1, city, state, zip, phone, fax, comments, specialized \
     FROM addressbook \
     WHERE displayname LIKE '%Aetna Better Health%' \
     ORDER BY address_id DESC LIMIT 1" 2>/dev/null)

# Query current count
CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM addressbook" 2>/dev/null || echo "0")

# Process result into variables
RECORD_FOUND="false"
R_NAME=""
R_ADDR=""
R_CITY=""
R_STATE=""
R_ZIP=""
R_PHONE=""
R_FAX=""
R_COMMENTS=""
R_SPECIALTY=""

if [ -n "$DB_RESULT" ]; then
    RECORD_FOUND="true"
    # Read tab-separated values
    R_NAME=$(echo "$DB_RESULT" | cut -f1)
    R_ADDR=$(echo "$DB_RESULT" | cut -f2)
    R_CITY=$(echo "$DB_RESULT" | cut -f3)
    R_STATE=$(echo "$DB_RESULT" | cut -f4)
    R_ZIP=$(echo "$DB_RESULT" | cut -f5)
    R_PHONE=$(echo "$DB_RESULT" | cut -f6)
    R_FAX=$(echo "$DB_RESULT" | cut -f7)
    R_COMMENTS=$(echo "$DB_RESULT" | cut -f8)
    R_SPECIALTY=$(echo "$DB_RESULT" | cut -f9)
fi

# Create JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "record_found": $RECORD_FOUND,
    "record": {
        "name": "$(echo $R_NAME | sed 's/"/\\"/g')",
        "address": "$(echo $R_ADDR | sed 's/"/\\"/g')",
        "city": "$(echo $R_CITY | sed 's/"/\\"/g')",
        "state": "$(echo $R_STATE | sed 's/"/\\"/g')",
        "zip": "$(echo $R_ZIP | sed 's/"/\\"/g')",
        "phone": "$(echo $R_PHONE | sed 's/"/\\"/g')",
        "fax": "$(echo $R_FAX | sed 's/"/\\"/g')",
        "comments": "$(echo $R_COMMENTS | sed 's/"/\\"/g')",
        "specialty": "$(echo $R_SPECIALTY | sed 's/"/\\"/g')"
    }
}
EOF

# Move to standard location with permission fix
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json