#!/bin/bash
# Export script for Document Flu Vaccination Task

echo "=== Exporting Document Flu Vaccine Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
echo "Task end timestamp: $TASK_END"

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=3

# Get initial counts from setup
INITIAL_IMM_COUNT=$(cat /tmp/initial_immunization_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL=$(cat /tmp/initial_total_immunizations.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get current immunization count for patient
CURRENT_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL=$(openemr_query "SELECT COUNT(*) FROM immunizations" 2>/dev/null || echo "0")

echo "Immunization count for patient: initial=$INITIAL_IMM_COUNT, current=$CURRENT_IMM_COUNT"
echo "Total immunizations: initial=$INITIAL_TOTAL, current=$CURRENT_TOTAL"

# Query for the most recent immunization for this patient
echo ""
echo "=== Querying immunizations for patient PID=$PATIENT_PID ==="
ALL_IMMS=$(openemr_query "SELECT id, patient_id, administered_date, immunization_id, manufacturer, lot_number, expiration_date, route, administration_site, amount_administered, amount_administered_unit, note, added_erroneously, create_date FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent immunizations:"
echo "$ALL_IMMS"
echo ""

# Get the newest immunization record (highest ID = newest)
NEWEST_IMM=$(openemr_query "SELECT id, patient_id, administered_date, immunization_id, manufacturer, lot_number, expiration_date, route, administration_site, amount_administered, amount_administered_unit, note, added_erroneously, UNIX_TIMESTAMP(create_date) as create_ts FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse immunization data
IMM_FOUND="false"
IMM_ID=""
IMM_PATIENT_ID=""
IMM_DATE=""
IMM_VACCINE_ID=""
IMM_MANUFACTURER=""
IMM_LOT=""
IMM_EXPIRATION=""
IMM_ROUTE=""
IMM_SITE=""
IMM_AMOUNT=""
IMM_UNIT=""
IMM_NOTE=""
IMM_ERRONEOUSLY=""
IMM_CREATE_TS=""

if [ -n "$NEWEST_IMM" ] && [ "$CURRENT_IMM_COUNT" -gt "$INITIAL_IMM_COUNT" ]; then
    IMM_FOUND="true"
    # Parse tab-separated values
    IMM_ID=$(echo "$NEWEST_IMM" | cut -f1)
    IMM_PATIENT_ID=$(echo "$NEWEST_IMM" | cut -f2)
    IMM_DATE=$(echo "$NEWEST_IMM" | cut -f3)
    IMM_VACCINE_ID=$(echo "$NEWEST_IMM" | cut -f4)
    IMM_MANUFACTURER=$(echo "$NEWEST_IMM" | cut -f5)
    IMM_LOT=$(echo "$NEWEST_IMM" | cut -f6)
    IMM_EXPIRATION=$(echo "$NEWEST_IMM" | cut -f7)
    IMM_ROUTE=$(echo "$NEWEST_IMM" | cut -f8)
    IMM_SITE=$(echo "$NEWEST_IMM" | cut -f9)
    IMM_AMOUNT=$(echo "$NEWEST_IMM" | cut -f10)
    IMM_UNIT=$(echo "$NEWEST_IMM" | cut -f11)
    IMM_NOTE=$(echo "$NEWEST_IMM" | cut -f12)
    IMM_ERRONEOUSLY=$(echo "$NEWEST_IMM" | cut -f13)
    IMM_CREATE_TS=$(echo "$NEWEST_IMM" | cut -f14)
    
    echo ""
    echo "New immunization found:"
    echo "  ID: $IMM_ID"
    echo "  Patient ID: $IMM_PATIENT_ID"
    echo "  Administered Date: $IMM_DATE"
    echo "  Manufacturer: $IMM_MANUFACTURER"
    echo "  Lot Number: $IMM_LOT"
    echo "  Expiration: $IMM_EXPIRATION"
    echo "  Route: $IMM_ROUTE"
    echo "  Site: $IMM_SITE"
    echo "  Amount: $IMM_AMOUNT $IMM_UNIT"
    echo "  Note: $IMM_NOTE"
    echo "  Create Timestamp: $IMM_CREATE_TS"
else
    echo "No new immunization found for patient"
    
    # Check if maybe the immunization was added but with wrong patient
    if [ "$CURRENT_TOTAL" -gt "$INITIAL_TOTAL" ]; then
        echo "Note: Total immunizations increased but not for target patient"
        WRONG_PATIENT_IMM=$(openemr_query "SELECT id, patient_id, manufacturer, lot_number FROM immunizations ORDER BY id DESC LIMIT 1" 2>/dev/null)
        echo "Most recent immunization (any patient): $WRONG_PATIENT_IMM"
    fi
fi

# Validate lot number
LOT_VALID="false"
if [ -n "$IMM_LOT" ]; then
    if echo "$IMM_LOT" | grep -qi "FL2024-3892"; then
        LOT_VALID="true"
        echo "Lot number matches expected (FL2024-3892)"
    else
        echo "Lot number does not match: expected FL2024-3892, got $IMM_LOT"
    fi
fi

# Validate manufacturer
MANUFACTURER_VALID="false"
if [ -n "$IMM_MANUFACTURER" ]; then
    if echo "$IMM_MANUFACTURER" | grep -qi "sanofi"; then
        MANUFACTURER_VALID="true"
        echo "Manufacturer matches expected (Sanofi)"
    else
        echo "Manufacturer does not match: expected Sanofi, got $IMM_MANUFACTURER"
    fi
fi

# Validate date is today
DATE_VALID="false"
TODAY=$(date +%Y-%m-%d)
if [ "$IMM_DATE" = "$TODAY" ]; then
    DATE_VALID="true"
    echo "Administered date is today ($TODAY)"
else
    # Allow for yesterday/tomorrow due to timezone issues
    YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || echo "")
    TOMORROW=$(date -d "tomorrow" +%Y-%m-%d 2>/dev/null || echo "")
    if [ "$IMM_DATE" = "$YESTERDAY" ] || [ "$IMM_DATE" = "$TOMORROW" ]; then
        DATE_VALID="true"
        echo "Administered date within acceptable range ($IMM_DATE)"
    else
        echo "Administered date outside expected range: $IMM_DATE (expected around $TODAY)"
    fi
fi

# Validate record was created during task (anti-gaming)
TIMING_VALID="false"
if [ -n "$IMM_CREATE_TS" ] && [ "$IMM_CREATE_TS" != "NULL" ] && [ "$IMM_CREATE_TS" -gt 0 ] 2>/dev/null; then
    if [ "$IMM_CREATE_TS" -ge "$TASK_START" ]; then
        TIMING_VALID="true"
        echo "Record created after task start (anti-gaming check passed)"
    else
        echo "Record may have existed before task (create_ts=$IMM_CREATE_TS, task_start=$TASK_START)"
    fi
else
    # If create_ts not available, use count comparison
    if [ "$CURRENT_IMM_COUNT" -gt "$INITIAL_IMM_COUNT" ]; then
        TIMING_VALID="true"
        echo "New record detected via count comparison"
    fi
fi

# Check additional fields
ROUTE_VALID="false"
if echo "$IMM_ROUTE" | grep -qi "intramuscular\|IM"; then
    ROUTE_VALID="true"
fi

SITE_VALID="false"
if echo "$IMM_SITE" | grep -qi "deltoid\|arm\|left"; then
    SITE_VALID="true"
fi

# Escape special characters for JSON
IMM_MANUFACTURER_ESC=$(echo "$IMM_MANUFACTURER" | sed 's/"/\\"/g' | tr '\n' ' ')
IMM_LOT_ESC=$(echo "$IMM_LOT" | sed 's/"/\\"/g' | tr '\n' ' ')
IMM_NOTE_ESC=$(echo "$IMM_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ')
IMM_ROUTE_ESC=$(echo "$IMM_ROUTE" | sed 's/"/\\"/g' | tr '\n' ' ')
IMM_SITE_ESC=$(echo "$IMM_SITE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/flu_vaccine_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_imm_count": ${INITIAL_IMM_COUNT:-0},
    "current_imm_count": ${CURRENT_IMM_COUNT:-0},
    "initial_total_imm": ${INITIAL_TOTAL:-0},
    "current_total_imm": ${CURRENT_TOTAL:-0},
    "task_start_time": ${TASK_START:-0},
    "task_end_time": ${TASK_END:-0},
    "immunization_found": $IMM_FOUND,
    "immunization": {
        "id": "$IMM_ID",
        "patient_id": "$IMM_PATIENT_ID",
        "administered_date": "$IMM_DATE",
        "vaccine_id": "$IMM_VACCINE_ID",
        "manufacturer": "$IMM_MANUFACTURER_ESC",
        "lot_number": "$IMM_LOT_ESC",
        "expiration_date": "$IMM_EXPIRATION",
        "route": "$IMM_ROUTE_ESC",
        "administration_site": "$IMM_SITE_ESC",
        "amount": "$IMM_AMOUNT",
        "amount_unit": "$IMM_UNIT",
        "note": "$IMM_NOTE_ESC",
        "create_timestamp": "${IMM_CREATE_TS:-0}"
    },
    "validation": {
        "lot_valid": $LOT_VALID,
        "manufacturer_valid": $MANUFACTURER_VALID,
        "date_valid": $DATE_VALID,
        "timing_valid": $TIMING_VALID,
        "route_valid": $ROUTE_VALID,
        "site_valid": $SITE_VALID
    },
    "expected_values": {
        "lot_number": "FL2024-3892",
        "manufacturer": "Sanofi Pasteur",
        "date": "$TODAY"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/document_flu_vaccine_result.json 2>/dev/null || sudo rm -f /tmp/document_flu_vaccine_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_flu_vaccine_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_flu_vaccine_result.json
chmod 666 /tmp/document_flu_vaccine_result.json 2>/dev/null || sudo chmod 666 /tmp/document_flu_vaccine_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/document_flu_vaccine_result.json"
cat /tmp/document_flu_vaccine_result.json

echo ""
echo "=== Export Complete ==="