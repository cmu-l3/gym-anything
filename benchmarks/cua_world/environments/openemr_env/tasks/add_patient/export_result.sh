#!/bin/bash
# Export script for Add Patient task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Add Patient Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current patient count
CURRENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM patient_data" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_patient_count 2>/dev/null || echo "0")

echo "Patient count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent patients to see what's actually in the database
echo ""
echo "=== DEBUG: Most recent patients in database ==="
openemr_query "SELECT pid, fname, lname, DOB, sex FROM patient_data ORDER BY pid DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check if the target patient was added using CASE-INSENSITIVE matching
# Use LOWER() for case-insensitive comparison and TRIM() for whitespace
echo "Checking for patient 'John TestPatient' (case-insensitive)..."
PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB, sex FROM patient_data WHERE LOWER(TRIM(fname))='john' AND LOWER(TRIM(lname))='testpatient' ORDER BY pid DESC LIMIT 1" 2>/dev/null)

# If not found with exact name, try partial match
if [ -z "$PATIENT_DATA" ]; then
    echo "Exact match not found, trying partial match..."
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB, sex FROM patient_data WHERE LOWER(fname) LIKE '%john%' AND LOWER(lname) LIKE '%testpatient%' ORDER BY pid DESC LIMIT 1" 2>/dev/null)
fi

# If still not found, check if any new patient was added (pid > initial count)
if [ -z "$PATIENT_DATA" ]; then
    echo "Partial match not found, checking for any new patient..."
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB, sex FROM patient_data WHERE pid > $INITIAL_COUNT ORDER BY pid DESC LIMIT 1" 2>/dev/null)
    if [ -n "$PATIENT_DATA" ]; then
        echo "Found new patient (not matching expected name):"
        echo "$PATIENT_DATA"
    fi
fi

# Parse patient data if found
PATIENT_FOUND="false"
PATIENT_PID=""
PATIENT_FNAME=""
PATIENT_LNAME=""
PATIENT_DOB=""
PATIENT_SEX=""

if [ -n "$PATIENT_DATA" ]; then
    PATIENT_FOUND="true"
    # Parse tab-separated values
    PATIENT_PID=$(echo "$PATIENT_DATA" | cut -f1)
    PATIENT_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
    PATIENT_LNAME=$(echo "$PATIENT_DATA" | cut -f3)
    PATIENT_DOB=$(echo "$PATIENT_DATA" | cut -f4)
    PATIENT_SEX=$(echo "$PATIENT_DATA" | cut -f5)
    echo "Patient found: PID=$PATIENT_PID, Name='$PATIENT_FNAME' '$PATIENT_LNAME', DOB=$PATIENT_DOB, Sex=$PATIENT_SEX"
else
    echo "Patient 'John TestPatient' NOT found in database"
fi

# Escape any special characters in patient data for JSON
# Replace double quotes with escaped quotes
PATIENT_FNAME_ESCAPED=$(echo "$PATIENT_FNAME" | sed 's/"/\\"/g')
PATIENT_LNAME_ESCAPED=$(echo "$PATIENT_LNAME" | sed 's/"/\\"/g')

# Create JSON in a temp file first, then move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/add_patient_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_patient_count": ${INITIAL_COUNT:-0},
    "current_patient_count": ${CURRENT_COUNT:-0},
    "patient_found": $PATIENT_FOUND,
    "patient": {
        "pid": "$PATIENT_PID",
        "fname": "$PATIENT_FNAME_ESCAPED",
        "lname": "$PATIENT_LNAME_ESCAPED",
        "dob": "$PATIENT_DOB",
        "sex": "$PATIENT_SEX"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location (handles permission issues)
# Remove old file first if possible, then copy (mv across filesystems may fail)
rm -f /tmp/add_patient_result.json 2>/dev/null || sudo rm -f /tmp/add_patient_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_patient_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_patient_result.json
chmod 666 /tmp/add_patient_result.json 2>/dev/null || sudo chmod 666 /tmp/add_patient_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_patient_result.json"
cat /tmp/add_patient_result.json

echo ""
echo "=== Export Complete ==="
