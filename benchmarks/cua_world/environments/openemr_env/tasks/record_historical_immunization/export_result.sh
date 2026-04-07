#!/bin/bash
# Export script for Record Historical Immunization Task

echo "=== Exporting Record Historical Immunization Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png
sleep 1

# Target patient
PATIENT_PID=3

# Get initial counts
INITIAL_IMM_COUNT=$(cat /tmp/initial_immunization_count 2>/dev/null || echo "0")
INITIAL_TOTAL=$(cat /tmp/total_immunization_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current immunization counts
CURRENT_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL=$(openemr_query "SELECT COUNT(*) FROM immunizations" 2>/dev/null || echo "0")

echo "Immunization count for patient: initial=$INITIAL_IMM_COUNT, current=$CURRENT_IMM_COUNT"
echo "Total immunizations: initial=$INITIAL_TOTAL, current=$CURRENT_TOTAL"

# Query for all immunizations for this patient (for debugging)
echo ""
echo "=== DEBUG: All immunizations for patient PID=$PATIENT_PID ==="
openemr_query "SELECT id, patient_id, immunization_id, cvx_code, administered_date, manufacturer, lot_number, administration_site, note, create_date FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Look for DTaP immunization with the expected date
# Search for various possible representations of DTaP
echo "Searching for DTaP immunization with date 2019-03-15..."
DTAP_RECORD=$(openemr_query "SELECT id, patient_id, immunization_id, cvx_code, administered_date, manufacturer, lot_number, administration_site, note, create_date FROM immunizations WHERE patient_id=$PATIENT_PID AND administered_date='2019-03-15' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# If not found with exact date, search for any new DTaP-like entry
if [ -z "$DTAP_RECORD" ]; then
    echo "No exact date match found, searching for any new immunization..."
    DTAP_RECORD=$(openemr_query "SELECT id, patient_id, immunization_id, cvx_code, administered_date, manufacturer, lot_number, administration_site, note, create_date FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Parse the immunization record
IMM_FOUND="false"
IMM_ID=""
IMM_PATIENT_ID=""
IMM_IMMUNIZATION_ID=""
IMM_CVX_CODE=""
IMM_DATE=""
IMM_MANUFACTURER=""
IMM_LOT_NUMBER=""
IMM_SITE=""
IMM_NOTE=""
IMM_CREATE_DATE=""

if [ -n "$DTAP_RECORD" ] && [ "$CURRENT_IMM_COUNT" -gt "$INITIAL_IMM_COUNT" ]; then
    IMM_FOUND="true"
    # Parse tab-separated values
    IMM_ID=$(echo "$DTAP_RECORD" | cut -f1)
    IMM_PATIENT_ID=$(echo "$DTAP_RECORD" | cut -f2)
    IMM_IMMUNIZATION_ID=$(echo "$DTAP_RECORD" | cut -f3)
    IMM_CVX_CODE=$(echo "$DTAP_RECORD" | cut -f4)
    IMM_DATE=$(echo "$DTAP_RECORD" | cut -f5)
    IMM_MANUFACTURER=$(echo "$DTAP_RECORD" | cut -f6)
    IMM_LOT_NUMBER=$(echo "$DTAP_RECORD" | cut -f7)
    IMM_SITE=$(echo "$DTAP_RECORD" | cut -f8)
    IMM_NOTE=$(echo "$DTAP_RECORD" | cut -f9)
    IMM_CREATE_DATE=$(echo "$DTAP_RECORD" | cut -f10)
    
    echo ""
    echo "Immunization record found:"
    echo "  ID: $IMM_ID"
    echo "  Patient ID: $IMM_PATIENT_ID"
    echo "  Immunization ID: $IMM_IMMUNIZATION_ID"
    echo "  CVX Code: $IMM_CVX_CODE"
    echo "  Administered Date: $IMM_DATE"
    echo "  Manufacturer: $IMM_MANUFACTURER"
    echo "  Lot Number: $IMM_LOT_NUMBER"
    echo "  Administration Site: $IMM_SITE"
    echo "  Note: $IMM_NOTE"
    echo "  Create Date: $IMM_CREATE_DATE"
else
    echo "No new immunization record found for patient"
fi

# Check if the date is historical (2019-03-15) not today
TODAY=$(date +%Y-%m-%d)
DATE_IS_HISTORICAL="false"
if [ "$IMM_DATE" = "2019-03-15" ]; then
    DATE_IS_HISTORICAL="true"
    echo "Date is correctly set to historical date (2019-03-15)"
elif [ "$IMM_DATE" = "$TODAY" ]; then
    echo "WARNING: Date is set to today ($TODAY) instead of historical date"
else
    echo "Date is: $IMM_DATE (expected: 2019-03-15)"
fi

# Check if vaccine is DTaP-related (CVX code 20 or contains DTaP in name)
VACCINE_IS_DTAP="false"
if [ "$IMM_CVX_CODE" = "20" ]; then
    VACCINE_IS_DTAP="true"
    echo "Vaccine CVX code matches DTaP (20)"
fi

# Also query the immunization name if we have an immunization_id
if [ -n "$IMM_IMMUNIZATION_ID" ]; then
    VACCINE_NAME=$(openemr_query "SELECT title FROM list_options WHERE list_id='immunizations' AND option_id='$IMM_IMMUNIZATION_ID' LIMIT 1" 2>/dev/null)
    echo "Vaccine name from list: $VACCINE_NAME"
    if echo "$VACCINE_NAME" | grep -qi "dtap\|diphtheria\|tetanus\|pertussis"; then
        VACCINE_IS_DTAP="true"
        echo "Vaccine name matches DTaP"
    fi
fi

# Check manufacturer matches
MANUFACTURER_CORRECT="false"
if echo "$IMM_MANUFACTURER" | grep -qi "sanofi"; then
    MANUFACTURER_CORRECT="true"
    echo "Manufacturer matches (Sanofi Pasteur)"
fi

# Check lot number matches
LOT_CORRECT="false"
if [ "$IMM_LOT_NUMBER" = "D2894AA" ]; then
    LOT_CORRECT="true"
    echo "Lot number matches (D2894AA)"
fi

# Check administration site
SITE_CORRECT="false"
if echo "$IMM_SITE" | grep -qi "left\|deltoid"; then
    SITE_CORRECT="true"
    echo "Administration site matches (Left Deltoid)"
fi

# Check for notes
NOTES_PRESENT="false"
if [ -n "$IMM_NOTE" ] && [ "$IMM_NOTE" != "NULL" ]; then
    NOTES_PRESENT="true"
    echo "Notes are present"
fi

# Escape special characters for JSON
IMM_MANUFACTURER_ESCAPED=$(echo "$IMM_MANUFACTURER" | sed 's/"/\\"/g' | tr '\n' ' ')
IMM_NOTE_ESCAPED=$(echo "$IMM_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ')
IMM_SITE_ESCAPED=$(echo "$IMM_SITE" | sed 's/"/\\"/g' | tr '\n' ' ')
VACCINE_NAME_ESCAPED=$(echo "$VACCINE_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/immunization_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_imm_count": ${INITIAL_IMM_COUNT:-0},
    "current_imm_count": ${CURRENT_IMM_COUNT:-0},
    "task_start_timestamp": ${TASK_START:-0},
    "immunization_found": $IMM_FOUND,
    "immunization": {
        "id": "$IMM_ID",
        "patient_id": "$IMM_PATIENT_ID",
        "immunization_id": "$IMM_IMMUNIZATION_ID",
        "cvx_code": "$IMM_CVX_CODE",
        "administered_date": "$IMM_DATE",
        "manufacturer": "$IMM_MANUFACTURER_ESCAPED",
        "lot_number": "$IMM_LOT_NUMBER",
        "administration_site": "$IMM_SITE_ESCAPED",
        "note": "$IMM_NOTE_ESCAPED",
        "create_date": "$IMM_CREATE_DATE",
        "vaccine_name": "$VACCINE_NAME_ESCAPED"
    },
    "validation": {
        "date_is_historical": $DATE_IS_HISTORICAL,
        "vaccine_is_dtap": $VACCINE_IS_DTAP,
        "manufacturer_correct": $MANUFACTURER_CORRECT,
        "lot_correct": $LOT_CORRECT,
        "site_correct": $SITE_CORRECT,
        "notes_present": $NOTES_PRESENT
    },
    "today_date": "$TODAY",
    "expected_date": "2019-03-15",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/historical_immunization_result.json 2>/dev/null || sudo rm -f /tmp/historical_immunization_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/historical_immunization_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/historical_immunization_result.json
chmod 666 /tmp/historical_immunization_result.json 2>/dev/null || sudo chmod 666 /tmp/historical_immunization_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/historical_immunization_result.json"
cat /tmp/historical_immunization_result.json

echo ""
echo "=== Export Complete ==="