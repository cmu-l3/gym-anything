#!/bin/bash
# Export script for Add Employer Information Task

echo "=== Exporting Add Employer Information Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task timing info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get target patient info
TARGET_PID=$(cat /tmp/target_patient_pid 2>/dev/null || echo "0")
TARGET_FNAME=$(cat /tmp/target_patient_fname 2>/dev/null || echo "Maria")
TARGET_LNAME=$(cat /tmp/target_patient_lname 2>/dev/null || echo "Klein")

# Get initial counts
INITIAL_EMPLOYER_COUNT=$(cat /tmp/initial_employer_count 2>/dev/null || echo "0")
INITIAL_EMPLOYER_ID=$(cat /tmp/initial_employer_id 2>/dev/null || echo "")

# Get current employer count
CURRENT_EMPLOYER_COUNT=$(openemr_query "SELECT COUNT(*) FROM employer_data" 2>/dev/null || echo "0")

echo "Employer count: initial=$INITIAL_EMPLOYER_COUNT, current=$CURRENT_EMPLOYER_COUNT"
echo "Target patient: $TARGET_FNAME $TARGET_LNAME (pid=$TARGET_PID)"

# Check if patient now has an employer association
echo ""
echo "=== Checking employer association for patient ==="
PATIENT_EMPLOYER_ID=$(openemr_query "SELECT employer FROM patient_data WHERE pid=$TARGET_PID" 2>/dev/null)
echo "Patient employer ID: $PATIENT_EMPLOYER_ID"

# Initialize variables
EMPLOYER_FOUND="false"
EMPLOYER_ID=""
EMPLOYER_NAME=""
EMPLOYER_STREET=""
EMPLOYER_CITY=""
EMPLOYER_STATE=""
EMPLOYER_POSTAL=""
EMPLOYER_COUNTRY=""

# If patient has employer association, get employer details
if [ -n "$PATIENT_EMPLOYER_ID" ] && [ "$PATIENT_EMPLOYER_ID" != "NULL" ] && [ "$PATIENT_EMPLOYER_ID" != "0" ]; then
    echo "Patient has employer ID: $PATIENT_EMPLOYER_ID"
    EMPLOYER_DATA=$(openemr_query "SELECT id, name, street, city, state, postal_code, country FROM employer_data WHERE id=$PATIENT_EMPLOYER_ID" 2>/dev/null)
    
    if [ -n "$EMPLOYER_DATA" ]; then
        EMPLOYER_FOUND="true"
        EMPLOYER_ID=$(echo "$EMPLOYER_DATA" | cut -f1)
        EMPLOYER_NAME=$(echo "$EMPLOYER_DATA" | cut -f2)
        EMPLOYER_STREET=$(echo "$EMPLOYER_DATA" | cut -f3)
        EMPLOYER_CITY=$(echo "$EMPLOYER_DATA" | cut -f4)
        EMPLOYER_STATE=$(echo "$EMPLOYER_DATA" | cut -f5)
        EMPLOYER_POSTAL=$(echo "$EMPLOYER_DATA" | cut -f6)
        EMPLOYER_COUNTRY=$(echo "$EMPLOYER_DATA" | cut -f7)
        
        echo ""
        echo "Employer details found:"
        echo "  ID: $EMPLOYER_ID"
        echo "  Name: $EMPLOYER_NAME"
        echo "  Street: $EMPLOYER_STREET"
        echo "  City: $EMPLOYER_CITY"
        echo "  State: $EMPLOYER_STATE"
        echo "  Postal: $EMPLOYER_POSTAL"
        echo "  Country: $EMPLOYER_COUNTRY"
    fi
fi

# If not found via patient association, check for newly created employer records
if [ "$EMPLOYER_FOUND" != "true" ]; then
    echo ""
    echo "Checking for newly created employer records..."
    
    # Look for employers containing "Precision" or "Manufacturing"
    NEW_EMPLOYER=$(openemr_query "SELECT id, name, street, city, state, postal_code, country FROM employer_data WHERE LOWER(name) LIKE '%precision%' OR LOWER(name) LIKE '%manufacturing%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEW_EMPLOYER" ]; then
        EMPLOYER_FOUND="true"
        EMPLOYER_ID=$(echo "$NEW_EMPLOYER" | cut -f1)
        EMPLOYER_NAME=$(echo "$NEW_EMPLOYER" | cut -f2)
        EMPLOYER_STREET=$(echo "$NEW_EMPLOYER" | cut -f3)
        EMPLOYER_CITY=$(echo "$NEW_EMPLOYER" | cut -f4)
        EMPLOYER_STATE=$(echo "$NEW_EMPLOYER" | cut -f5)
        EMPLOYER_POSTAL=$(echo "$NEW_EMPLOYER" | cut -f6)
        EMPLOYER_COUNTRY=$(echo "$NEW_EMPLOYER" | cut -f7)
        
        echo "Found employer by name search:"
        echo "  ID: $EMPLOYER_ID"
        echo "  Name: $EMPLOYER_NAME"
    fi
fi

# Check if this is a newly created employer
NEW_EMPLOYER_CREATED="false"
if [ -n "$EMPLOYER_ID" ]; then
    # Compare with initial employer ID - if different or initial was empty, it's new
    if [ "$EMPLOYER_ID" != "$INITIAL_EMPLOYER_ID" ] && [ "$CURRENT_EMPLOYER_COUNT" -gt "$INITIAL_EMPLOYER_COUNT" ]; then
        NEW_EMPLOYER_CREATED="true"
        echo "New employer record was created (ID: $EMPLOYER_ID)"
    elif [ "$EMPLOYER_ID" != "$INITIAL_EMPLOYER_ID" ]; then
        # Employer changed but count didn't increase - might have reused existing
        echo "Employer association changed (previous: $INITIAL_EMPLOYER_ID, current: $EMPLOYER_ID)"
    fi
fi

# Debug: Show all recent employer records
echo ""
echo "=== DEBUG: Recent employer records ==="
openemr_query "SELECT id, name, street, city, state FROM employer_data ORDER BY id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="

# Escape special characters for JSON
EMPLOYER_NAME_ESC=$(echo "$EMPLOYER_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
EMPLOYER_STREET_ESC=$(echo "$EMPLOYER_STREET" | sed 's/"/\\"/g' | tr '\n' ' ')
EMPLOYER_CITY_ESC=$(echo "$EMPLOYER_CITY" | sed 's/"/\\"/g' | tr '\n' ' ')
EMPLOYER_STATE_ESC=$(echo "$EMPLOYER_STATE" | sed 's/"/\\"/g' | tr '\n' ' ')
EMPLOYER_POSTAL_ESC=$(echo "$EMPLOYER_POSTAL" | sed 's/"/\\"/g' | tr '\n' ' ')
EMPLOYER_COUNTRY_ESC=$(echo "$EMPLOYER_COUNTRY" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/employer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient": {
        "pid": "$TARGET_PID",
        "fname": "$TARGET_FNAME",
        "lname": "$TARGET_LNAME"
    },
    "initial_employer_count": ${INITIAL_EMPLOYER_COUNT:-0},
    "current_employer_count": ${CURRENT_EMPLOYER_COUNT:-0},
    "initial_employer_id": "$INITIAL_EMPLOYER_ID",
    "employer_found": $EMPLOYER_FOUND,
    "new_employer_created": $NEW_EMPLOYER_CREATED,
    "employer": {
        "id": "$EMPLOYER_ID",
        "name": "$EMPLOYER_NAME_ESC",
        "street": "$EMPLOYER_STREET_ESC",
        "city": "$EMPLOYER_CITY_ESC",
        "state": "$EMPLOYER_STATE_ESC",
        "postal_code": "$EMPLOYER_POSTAL_ESC",
        "country": "$EMPLOYER_COUNTRY_ESC"
    },
    "patient_employer_id": "$PATIENT_EMPLOYER_ID",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/add_employer_result.json 2>/dev/null || sudo rm -f /tmp/add_employer_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_employer_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_employer_result.json
chmod 666 /tmp/add_employer_result.json 2>/dev/null || sudo chmod 666 /tmp/add_employer_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_employer_result.json"
cat /tmp/add_employer_result.json

echo ""
echo "=== Export Complete ==="