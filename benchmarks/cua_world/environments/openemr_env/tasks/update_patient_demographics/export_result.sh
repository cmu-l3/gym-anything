#!/bin/bash
# Export script for Update Patient Demographics Task

echo "=== Exporting Update Patient Demographics Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=3

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Load initial state
INITIAL_STREET=""
INITIAL_CITY=""
INITIAL_STATE=""
INITIAL_POSTAL=""
INITIAL_PHONE_HOME=""
INITIAL_PHONE_CELL=""

if [ -f /tmp/initial_demographics.json ]; then
    INITIAL_STREET=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['initial_values'].get('street', ''))" 2>/dev/null || echo "")
    INITIAL_CITY=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['initial_values'].get('city', ''))" 2>/dev/null || echo "")
    INITIAL_STATE=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['initial_values'].get('state', ''))" 2>/dev/null || echo "")
    INITIAL_POSTAL=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['initial_values'].get('postal_code', ''))" 2>/dev/null || echo "")
    INITIAL_PHONE_HOME=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['initial_values'].get('phone_home', ''))" 2>/dev/null || echo "")
    INITIAL_PHONE_CELL=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['initial_values'].get('phone_cell', ''))" 2>/dev/null || echo "")
fi

echo "Initial values loaded from setup:"
echo "  Street: '$INITIAL_STREET'"
echo "  City: '$INITIAL_CITY'"
echo "  State: '$INITIAL_STATE'"
echo "  Postal: '$INITIAL_POSTAL'"
echo "  Home Phone: '$INITIAL_PHONE_HOME'"
echo "  Cell Phone: '$INITIAL_PHONE_CELL'"

# Query current patient demographics
echo ""
echo "=== Querying current patient demographics ==="
CURRENT_DATA=$(openemr_query "SELECT street, city, state, postal_code, phone_home, phone_cell, fname, lname, DOB, sex FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Raw query result: $CURRENT_DATA"

# Parse current values
CURRENT_STREET=$(echo "$CURRENT_DATA" | cut -f1)
CURRENT_CITY=$(echo "$CURRENT_DATA" | cut -f2)
CURRENT_STATE=$(echo "$CURRENT_DATA" | cut -f3)
CURRENT_POSTAL=$(echo "$CURRENT_DATA" | cut -f4)
CURRENT_PHONE_HOME=$(echo "$CURRENT_DATA" | cut -f5)
CURRENT_PHONE_CELL=$(echo "$CURRENT_DATA" | cut -f6)
CURRENT_FNAME=$(echo "$CURRENT_DATA" | cut -f7)
CURRENT_LNAME=$(echo "$CURRENT_DATA" | cut -f8)
CURRENT_DOB=$(echo "$CURRENT_DATA" | cut -f9)
CURRENT_SEX=$(echo "$CURRENT_DATA" | cut -f10)

# Handle NULL values
[ "$CURRENT_STREET" = "NULL" ] && CURRENT_STREET=""
[ "$CURRENT_CITY" = "NULL" ] && CURRENT_CITY=""
[ "$CURRENT_STATE" = "NULL" ] && CURRENT_STATE=""
[ "$CURRENT_POSTAL" = "NULL" ] && CURRENT_POSTAL=""
[ "$CURRENT_PHONE_HOME" = "NULL" ] && CURRENT_PHONE_HOME=""
[ "$CURRENT_PHONE_CELL" = "NULL" ] && CURRENT_PHONE_CELL=""

echo ""
echo "Current values:"
echo "  Street: '$CURRENT_STREET'"
echo "  City: '$CURRENT_CITY'"
echo "  State: '$CURRENT_STATE'"
echo "  Postal: '$CURRENT_POSTAL'"
echo "  Home Phone: '$CURRENT_PHONE_HOME'"
echo "  Cell Phone: '$CURRENT_PHONE_CELL'"
echo "  Name: '$CURRENT_FNAME $CURRENT_LNAME'"
echo "  DOB: '$CURRENT_DOB'"
echo "  Sex: '$CURRENT_SEX'"

# Determine what changed
STREET_CHANGED="false"
CITY_CHANGED="false"
STATE_CHANGED="false"
POSTAL_CHANGED="false"
PHONE_HOME_CHANGED="false"
PHONE_CELL_CHANGED="false"

[ "$CURRENT_STREET" != "$INITIAL_STREET" ] && STREET_CHANGED="true"
[ "$CURRENT_CITY" != "$INITIAL_CITY" ] && CITY_CHANGED="true"
[ "$CURRENT_STATE" != "$INITIAL_STATE" ] && STATE_CHANGED="true"
[ "$CURRENT_POSTAL" != "$INITIAL_POSTAL" ] && POSTAL_CHANGED="true"
[ "$CURRENT_PHONE_HOME" != "$INITIAL_PHONE_HOME" ] && PHONE_HOME_CHANGED="true"
[ "$CURRENT_PHONE_CELL" != "$INITIAL_PHONE_CELL" ] && PHONE_CELL_CHANGED="true"

# Check if any data was modified
ANY_CHANGE="false"
if [ "$STREET_CHANGED" = "true" ] || [ "$CITY_CHANGED" = "true" ] || [ "$POSTAL_CHANGED" = "true" ] || [ "$PHONE_HOME_CHANGED" = "true" ] || [ "$PHONE_CELL_CHANGED" = "true" ]; then
    ANY_CHANGE="true"
fi

echo ""
echo "Changes detected:"
echo "  Street changed: $STREET_CHANGED"
echo "  City changed: $CITY_CHANGED"
echo "  State changed: $STATE_CHANGED"
echo "  Postal changed: $POSTAL_CHANGED"
echo "  Home Phone changed: $PHONE_HOME_CHANGED"
echo "  Cell Phone changed: $PHONE_CELL_CHANGED"
echo "  Any change: $ANY_CHANGE"

# Escape special characters for JSON
CURRENT_STREET_ESC=$(echo "$CURRENT_STREET" | sed 's/"/\\"/g')
CURRENT_CITY_ESC=$(echo "$CURRENT_CITY" | sed 's/"/\\"/g')
CURRENT_FNAME_ESC=$(echo "$CURRENT_FNAME" | sed 's/"/\\"/g')
CURRENT_LNAME_ESC=$(echo "$CURRENT_LNAME" | sed 's/"/\\"/g')
INITIAL_STREET_ESC=$(echo "$INITIAL_STREET" | sed 's/"/\\"/g')
INITIAL_CITY_ESC=$(echo "$INITIAL_CITY" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/demographics_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "patient_identity": {
        "fname": "$CURRENT_FNAME_ESC",
        "lname": "$CURRENT_LNAME_ESC",
        "dob": "$CURRENT_DOB",
        "sex": "$CURRENT_SEX"
    },
    "initial_values": {
        "street": "$INITIAL_STREET_ESC",
        "city": "$INITIAL_CITY_ESC",
        "state": "$INITIAL_STATE",
        "postal_code": "$INITIAL_POSTAL",
        "phone_home": "$INITIAL_PHONE_HOME",
        "phone_cell": "$INITIAL_PHONE_CELL"
    },
    "current_values": {
        "street": "$CURRENT_STREET_ESC",
        "city": "$CURRENT_CITY_ESC",
        "state": "$CURRENT_STATE",
        "postal_code": "$CURRENT_POSTAL",
        "phone_home": "$CURRENT_PHONE_HOME",
        "phone_cell": "$CURRENT_PHONE_CELL"
    },
    "changes_detected": {
        "street": $STREET_CHANGED,
        "city": $CITY_CHANGED,
        "state": $STATE_CHANGED,
        "postal_code": $POSTAL_CHANGED,
        "phone_home": $PHONE_HOME_CHANGED,
        "phone_cell": $PHONE_CELL_CHANGED,
        "any_change": $ANY_CHANGE
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/update_demographics_result.json 2>/dev/null || sudo rm -f /tmp/update_demographics_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/update_demographics_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/update_demographics_result.json
chmod 666 /tmp/update_demographics_result.json 2>/dev/null || sudo chmod 666 /tmp/update_demographics_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/update_demographics_result.json"
cat /tmp/update_demographics_result.json

echo ""
echo "=== Export Complete ==="