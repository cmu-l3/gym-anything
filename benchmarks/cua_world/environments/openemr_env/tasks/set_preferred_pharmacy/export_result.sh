#!/bin/bash
# Export script for Set Preferred Pharmacy Task

echo "=== Exporting Set Preferred Pharmacy Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target values
PATIENT_PID=5
TARGET_PHARMACY_ID=50
TARGET_PHARMACY_NAME="CVS Pharmacy - Downtown"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial pharmacy value
INITIAL_PHARMACY=$(cat /tmp/initial_pharmacy.txt 2>/dev/null || echo "NULL")

# Query current pharmacy assignment
echo "Querying current pharmacy assignment..."
CURRENT_PHARMACY_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(pharmacy_id, 'NULL') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "NULL")

echo "Pharmacy assignment: initial='$INITIAL_PHARMACY', current='$CURRENT_PHARMACY_ID'"

# Get pharmacy details if one is assigned
PHARMACY_NAME=""
PHARMACY_NCPDP=""
PHARMACY_ADDRESS=""
PHARMACY_FOUND="false"

if [ -n "$CURRENT_PHARMACY_ID" ] && [ "$CURRENT_PHARMACY_ID" != "NULL" ]; then
    echo "Fetching pharmacy details for id=$CURRENT_PHARMACY_ID..."
    PHARMACY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT name, ncpdp, CONCAT(address, ', ', city, ', ', state, ' ', zip) as full_address 
         FROM pharmacies WHERE id=$CURRENT_PHARMACY_ID" 2>/dev/null)
    
    if [ -n "$PHARMACY_DATA" ]; then
        PHARMACY_FOUND="true"
        PHARMACY_NAME=$(echo "$PHARMACY_DATA" | cut -f1)
        PHARMACY_NCPDP=$(echo "$PHARMACY_DATA" | cut -f2)
        PHARMACY_ADDRESS=$(echo "$PHARMACY_DATA" | cut -f3)
        echo "Pharmacy found: $PHARMACY_NAME"
    fi
fi

# Check if the correct pharmacy was assigned
CORRECT_PHARMACY="false"
if [ "$CURRENT_PHARMACY_ID" = "$TARGET_PHARMACY_ID" ]; then
    CORRECT_PHARMACY="true"
    echo "CORRECT: Target pharmacy was assigned"
elif echo "$PHARMACY_NAME" | grep -qi "CVS.*Downtown"; then
    CORRECT_PHARMACY="true"
    echo "CORRECT: Pharmacy name matches target (by name)"
else
    echo "Pharmacy does not match target"
fi

# Check if pharmacy was changed from initial state
PHARMACY_CHANGED="false"
if [ "$CURRENT_PHARMACY_ID" != "$INITIAL_PHARMACY" ] && [ "$CURRENT_PHARMACY_ID" != "NULL" ]; then
    PHARMACY_CHANGED="true"
    echo "Pharmacy was changed from initial state"
fi

# Debug: Show patient record
echo ""
echo "=== DEBUG: Patient record ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT pid, fname, lname, pharmacy_id FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null
echo "=== END DEBUG ==="

# Escape special characters for JSON
PHARMACY_NAME_ESCAPED=$(echo "$PHARMACY_NAME" | sed 's/"/\\"/g')
PHARMACY_ADDRESS_ESCAPED=$(echo "$PHARMACY_ADDRESS" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/pharmacy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "target_pharmacy_id": $TARGET_PHARMACY_ID,
    "target_pharmacy_name": "$TARGET_PHARMACY_NAME",
    "initial_pharmacy_id": "$INITIAL_PHARMACY",
    "current_pharmacy_id": "$CURRENT_PHARMACY_ID",
    "pharmacy_found": $PHARMACY_FOUND,
    "pharmacy_details": {
        "name": "$PHARMACY_NAME_ESCAPED",
        "ncpdp": "$PHARMACY_NCPDP",
        "address": "$PHARMACY_ADDRESS_ESCAPED"
    },
    "validation": {
        "pharmacy_changed": $PHARMACY_CHANGED,
        "correct_pharmacy": $CORRECT_PHARMACY
    },
    "timestamps": {
        "task_start": $TASK_START,
        "task_end": $TASK_END
    },
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/set_pharmacy_result.json 2>/dev/null || sudo rm -f /tmp/set_pharmacy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/set_pharmacy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/set_pharmacy_result.json
chmod 666 /tmp/set_pharmacy_result.json 2>/dev/null || sudo chmod 666 /tmp/set_pharmacy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/set_pharmacy_result.json"
cat /tmp/set_pharmacy_result.json

echo ""
echo "=== Export Complete ==="