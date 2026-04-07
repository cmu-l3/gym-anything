#!/bin/bash
# Export script for Document Medication Administration Task

echo "=== Exporting Medication Administration Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Target patient
PATIENT_PID=3

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_IMM_COUNT=$(cat /tmp/initial_immunization_count 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Initial immunization count: $INITIAL_IMM_COUNT"
echo "Initial forms count: $INITIAL_FORMS_COUNT"

# Get current immunization count for patient
CURRENT_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Current immunization count: $CURRENT_IMM_COUNT"
echo "Current forms count: $CURRENT_FORMS_COUNT"

# Check for new immunization records
echo ""
echo "=== Checking for new immunization records ==="

# Query all immunization records for patient, ordered by ID descending (newest first)
ALL_IMM=$(openemr_query "SELECT id, patient_id, immunization_id, cvx_code, manufacturer, lot_number, administered_date, administration_site, note, route, administered_by_id, create_date FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "All immunizations for patient:"
echo "$ALL_IMM"

# Find new immunizations (created after initial snapshot)
NEW_IMM_FOUND="false"
NEW_IMM_ID=""
NEW_IMM_NAME=""
NEW_IMM_DATE=""
NEW_IMM_SITE=""
NEW_IMM_ROUTE=""
NEW_IMM_NOTE=""
NEW_IMM_DOSE=""

# Get the newest immunization record if count increased
if [ "$CURRENT_IMM_COUNT" -gt "$INITIAL_IMM_COUNT" ]; then
    echo ""
    echo "New immunization record detected!"
    
    # Get the newest record
    NEWEST_IMM=$(openemr_query "SELECT id, immunization_id, administered_date, administration_site, route, note, manufacturer, lot_number, amount_administered, amount_administered_unit FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_IMM" ]; then
        NEW_IMM_FOUND="true"
        NEW_IMM_ID=$(echo "$NEWEST_IMM" | cut -f1)
        NEW_IMM_NAME=$(echo "$NEWEST_IMM" | cut -f2)
        NEW_IMM_DATE=$(echo "$NEWEST_IMM" | cut -f3)
        NEW_IMM_SITE=$(echo "$NEWEST_IMM" | cut -f4)
        NEW_IMM_ROUTE=$(echo "$NEWEST_IMM" | cut -f5)
        NEW_IMM_NOTE=$(echo "$NEWEST_IMM" | cut -f6)
        NEW_IMM_MANUFACTURER=$(echo "$NEWEST_IMM" | cut -f7)
        NEW_IMM_LOT=$(echo "$NEWEST_IMM" | cut -f8)
        NEW_IMM_AMOUNT=$(echo "$NEWEST_IMM" | cut -f9)
        NEW_IMM_UNIT=$(echo "$NEWEST_IMM" | cut -f10)
        
        echo "New immunization details:"
        echo "  ID: $NEW_IMM_ID"
        echo "  Name/Type: $NEW_IMM_NAME"
        echo "  Date: $NEW_IMM_DATE"
        echo "  Site: $NEW_IMM_SITE"
        echo "  Route: $NEW_IMM_ROUTE"
        echo "  Note: $NEW_IMM_NOTE"
        echo "  Amount: $NEW_IMM_AMOUNT $NEW_IMM_UNIT"
    fi
else
    echo "No new immunization records found (count: $INITIAL_IMM_COUNT -> $CURRENT_IMM_COUNT)"
fi

# Also check the immunization by looking for B12 keywords
echo ""
echo "=== Searching for B12/Cyanocobalamin in records ==="
B12_RECORDS=$(openemr_query "SELECT id, immunization_id, note, administration_site, route FROM immunizations WHERE patient_id=$PATIENT_PID AND (immunization_id LIKE '%B12%' OR immunization_id LIKE '%cyanocobalamin%' OR immunization_id LIKE '%Cyanocobalamin%' OR note LIKE '%B12%' OR note LIKE '%cyanocobalamin%' OR note LIKE '%vitamin%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "B12-related records found:"
echo "$B12_RECORDS"

# Check for any medication in forms/encounters
echo ""
echo "=== Checking forms for medication records ==="
NEW_FORMS=$(openemr_query "SELECT id, date, form_name, form_id FROM forms WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent forms:"
echo "$NEW_FORMS"

# Check if medication name contains B12 keywords
MEDICATION_MATCH="false"
MEDICATION_NAME_LOWER=$(echo "$NEW_IMM_NAME $NEW_IMM_NOTE" | tr '[:upper:]' '[:lower:]')
if echo "$MEDICATION_NAME_LOWER" | grep -qiE "(b12|b-12|cyanocobalamin|cobalamin|vitamin)"; then
    MEDICATION_MATCH="true"
    echo "Medication matches B12/Cyanocobalamin"
fi

# Check if route matches IM/intramuscular
ROUTE_MATCH="false"
ROUTE_LOWER=$(echo "$NEW_IMM_ROUTE" | tr '[:upper:]' '[:lower:]')
if echo "$ROUTE_LOWER" | grep -qiE "(im|intramuscular|intra-muscular)"; then
    ROUTE_MATCH="true"
    echo "Route matches Intramuscular"
fi

# Check if site is documented
SITE_MATCH="false"
SITE_LOWER=$(echo "$NEW_IMM_SITE" | tr '[:upper:]' '[:lower:]')
if echo "$SITE_LOWER" | grep -qiE "(deltoid|arm|shoulder|left|right)"; then
    SITE_MATCH="true"
    echo "Site matches deltoid/arm region"
elif [ -n "$NEW_IMM_SITE" ] && [ "$NEW_IMM_SITE" != "NULL" ]; then
    # Any site documented is partial credit
    SITE_MATCH="partial"
    echo "Site documented: $NEW_IMM_SITE"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' '
}

NEW_IMM_NAME_ESC=$(escape_json "$NEW_IMM_NAME")
NEW_IMM_NOTE_ESC=$(escape_json "$NEW_IMM_NOTE")
NEW_IMM_SITE_ESC=$(escape_json "$NEW_IMM_SITE")
NEW_IMM_ROUTE_ESC=$(escape_json "$NEW_IMM_ROUTE")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/med_admin_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "initial_immunization_count": ${INITIAL_IMM_COUNT:-0},
    "current_immunization_count": ${CURRENT_IMM_COUNT:-0},
    "initial_forms_count": ${INITIAL_FORMS_COUNT:-0},
    "current_forms_count": ${CURRENT_FORMS_COUNT:-0},
    "new_immunization_found": $NEW_IMM_FOUND,
    "immunization_record": {
        "id": "$NEW_IMM_ID",
        "immunization_name": "$NEW_IMM_NAME_ESC",
        "date_administered": "$NEW_IMM_DATE",
        "site": "$NEW_IMM_SITE_ESC",
        "route": "$NEW_IMM_ROUTE_ESC",
        "note": "$NEW_IMM_NOTE_ESC",
        "amount": "$NEW_IMM_AMOUNT",
        "unit": "$NEW_IMM_UNIT"
    },
    "validation": {
        "medication_matches_b12": $MEDICATION_MATCH,
        "route_matches_im": $ROUTE_MATCH,
        "site_documented": "$SITE_MATCH"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/medication_administration_result.json 2>/dev/null || sudo rm -f /tmp/medication_administration_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/medication_administration_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/medication_administration_result.json
chmod 666 /tmp/medication_administration_result.json 2>/dev/null || sudo chmod 666 /tmp/medication_administration_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/medication_administration_result.json"
cat /tmp/medication_administration_result.json
echo ""
echo "=== Export Complete ==="