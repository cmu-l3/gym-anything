#!/bin/bash
# Export script for Add Patient Guarantor task

echo "=== Exporting Add Patient Guarantor Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png
sleep 1

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get patient PID
PATIENT_PID=$(cat /tmp/task_patient_pid.txt 2>/dev/null || echo "0")
PATIENT_FNAME="Pedro"
PATIENT_LNAME="Gusikowski"

echo "Patient PID: $PATIENT_PID"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Query current guarantor information
echo ""
echo "=== Querying guarantor information ==="

if [ "$PATIENT_PID" != "0" ] && [ -n "$PATIENT_PID" ]; then
    # Query all guarantor fields
    GUARDIAN_DATA=$(openemr_query "SELECT guardiansname, guardianstreet, guardiancity, guardianstate, guardianpostalcode, guardianphone FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
    
    echo "Raw guardian data: $GUARDIAN_DATA"
    
    # Parse the tab-separated values
    GUARDIAN_NAME=$(echo "$GUARDIAN_DATA" | cut -f1)
    GUARDIAN_STREET=$(echo "$GUARDIAN_DATA" | cut -f2)
    GUARDIAN_CITY=$(echo "$GUARDIAN_DATA" | cut -f3)
    GUARDIAN_STATE=$(echo "$GUARDIAN_DATA" | cut -f4)
    GUARDIAN_ZIP=$(echo "$GUARDIAN_DATA" | cut -f5)
    GUARDIAN_PHONE=$(echo "$GUARDIAN_DATA" | cut -f6)
    
    echo ""
    echo "Parsed guarantor fields:"
    echo "  Name: '$GUARDIAN_NAME'"
    echo "  Street: '$GUARDIAN_STREET'"
    echo "  City: '$GUARDIAN_CITY'"
    echo "  State: '$GUARDIAN_STATE'"
    echo "  Zip: '$GUARDIAN_ZIP'"
    echo "  Phone: '$GUARDIAN_PHONE'"
    
    # Check if any data was added
    DATA_PRESENT="false"
    if [ -n "$GUARDIAN_NAME" ] && [ "$GUARDIAN_NAME" != "NULL" ] && [ ${#GUARDIAN_NAME} -gt 2 ]; then
        DATA_PRESENT="true"
    fi
    
    # Also try alternative field names that might exist
    ALT_GUARDIAN=$(openemr_query "SELECT pid FROM patient_data WHERE pid=$PATIENT_PID AND (guardiansname IS NOT NULL AND guardiansname != '')" 2>/dev/null)
    if [ -n "$ALT_GUARDIAN" ]; then
        echo "Confirmed: Guardian name field is populated"
    fi
else
    echo "ERROR: Patient PID not found"
    GUARDIAN_NAME=""
    GUARDIAN_STREET=""
    GUARDIAN_CITY=""
    GUARDIAN_STATE=""
    GUARDIAN_ZIP=""
    GUARDIAN_PHONE=""
    DATA_PRESENT="false"
fi

# Get initial state for comparison
INITIAL_STATE=$(cat /tmp/initial_guardian_state.txt 2>/dev/null || echo "")
echo ""
echo "Initial guardian state was: '$INITIAL_STATE'"

# Check if data changed from initial state
DATA_CHANGED="false"
if [ "$DATA_PRESENT" = "true" ]; then
    if [ -z "$INITIAL_STATE" ] || [ "$INITIAL_STATE" = "					" ]; then
        DATA_CHANGED="true"
        echo "Data was added (fields were empty before)"
    elif [ "$GUARDIAN_DATA" != "$INITIAL_STATE" ]; then
        DATA_CHANGED="true"
        echo "Data was modified"
    fi
fi

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

GUARDIAN_NAME_ESC=$(escape_json "$GUARDIAN_NAME")
GUARDIAN_STREET_ESC=$(escape_json "$GUARDIAN_STREET")
GUARDIAN_CITY_ESC=$(escape_json "$GUARDIAN_CITY")
GUARDIAN_STATE_ESC=$(escape_json "$GUARDIAN_STATE")
GUARDIAN_ZIP_ESC=$(escape_json "$GUARDIAN_ZIP")
GUARDIAN_PHONE_ESC=$(escape_json "$GUARDIAN_PHONE")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/guarantor_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "patient_fname": "$PATIENT_FNAME",
    "patient_lname": "$PATIENT_LNAME",
    "guarantor_data": {
        "name": "$GUARDIAN_NAME_ESC",
        "street": "$GUARDIAN_STREET_ESC",
        "city": "$GUARDIAN_CITY_ESC",
        "state": "$GUARDIAN_STATE_ESC",
        "zip": "$GUARDIAN_ZIP_ESC",
        "phone": "$GUARDIAN_PHONE_ESC"
    },
    "data_present": $DATA_PRESENT,
    "data_changed": $DATA_CHANGED,
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_final": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/add_guarantor_result.json 2>/dev/null || sudo rm -f /tmp/add_guarantor_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_guarantor_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_guarantor_result.json
chmod 666 /tmp/add_guarantor_result.json 2>/dev/null || sudo chmod 666 /tmp/add_guarantor_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/add_guarantor_result.json
echo ""
echo "=== Export Complete ==="