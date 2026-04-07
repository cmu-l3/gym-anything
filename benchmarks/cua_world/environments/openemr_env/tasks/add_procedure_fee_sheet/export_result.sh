#!/bin/bash
# Export script for Add Procedure to Fee Sheet task

echo "=== Exporting Add Procedure to Fee Sheet Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=5
EXPECTED_CODE="99213"

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts recorded during setup
INITIAL_BILLING_COUNT=$(cat /tmp/initial_billing_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_BILLING=$(cat /tmp/initial_total_billing.txt 2>/dev/null || echo "0")
PATIENT_ENCOUNTER=$(cat /tmp/patient_encounter_id.txt 2>/dev/null || echo "0")

# Get current billing count for this patient with code 99213
CURRENT_BILLING_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code='$EXPECTED_CODE'" 2>/dev/null || echo "0")

# Get total billing count
CURRENT_TOTAL_BILLING=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Billing count for $EXPECTED_CODE: initial=$INITIAL_BILLING_COUNT, current=$CURRENT_BILLING_COUNT"
echo "Total billing count: initial=$INITIAL_TOTAL_BILLING, current=$CURRENT_TOTAL_BILLING"

# Query for the most recent billing entry with code 99213 for this patient
echo ""
echo "=== Querying billing entries for patient PID=$PATIENT_PID ==="
BILLING_ENTRY=$(openemr_query "SELECT id, date, code_type, code, pid, encounter, fee, units, modifier, activity, billed FROM billing WHERE pid=$PATIENT_PID AND code='$EXPECTED_CODE' ORDER BY id DESC LIMIT 1" 2>/dev/null)

echo "Most recent 99213 billing entry:"
echo "$BILLING_ENTRY"

# Also show all recent billing entries for debugging
echo ""
echo "All recent billing entries for patient:"
openemr_query "SELECT id, date, code_type, code, encounter, activity FROM billing WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null

# Parse billing entry data
BILLING_FOUND="false"
BILLING_ID=""
BILLING_DATE=""
BILLING_CODE_TYPE=""
BILLING_CODE=""
BILLING_ENCOUNTER=""
BILLING_FEE=""
BILLING_UNITS=""
BILLING_ACTIVITY=""
BILLING_BILLED=""

if [ -n "$BILLING_ENTRY" ]; then
    BILLING_FOUND="true"
    # Parse tab-separated values
    BILLING_ID=$(echo "$BILLING_ENTRY" | cut -f1)
    BILLING_DATE=$(echo "$BILLING_ENTRY" | cut -f2)
    BILLING_CODE_TYPE=$(echo "$BILLING_ENTRY" | cut -f3)
    BILLING_CODE=$(echo "$BILLING_ENTRY" | cut -f4)
    BILLING_PID=$(echo "$BILLING_ENTRY" | cut -f5)
    BILLING_ENCOUNTER=$(echo "$BILLING_ENTRY" | cut -f6)
    BILLING_FEE=$(echo "$BILLING_ENTRY" | cut -f7)
    BILLING_UNITS=$(echo "$BILLING_ENTRY" | cut -f8)
    BILLING_MODIFIER=$(echo "$BILLING_ENTRY" | cut -f9)
    BILLING_ACTIVITY=$(echo "$BILLING_ENTRY" | cut -f10)
    BILLING_BILLED=$(echo "$BILLING_ENTRY" | cut -f11)
    
    echo ""
    echo "Parsed billing entry:"
    echo "  ID: $BILLING_ID"
    echo "  Date: $BILLING_DATE"
    echo "  Code Type: $BILLING_CODE_TYPE"
    echo "  Code: $BILLING_CODE"
    echo "  Patient PID: $BILLING_PID"
    echo "  Encounter: $BILLING_ENCOUNTER"
    echo "  Fee: $BILLING_FEE"
    echo "  Units: $BILLING_UNITS"
    echo "  Activity: $BILLING_ACTIVITY"
    echo "  Billed: $BILLING_BILLED"
fi

# Check if this is a new entry (ID > what we had before)
NEW_ENTRY="false"
if [ "$CURRENT_BILLING_COUNT" -gt "$INITIAL_BILLING_COUNT" ]; then
    NEW_ENTRY="true"
    echo "New billing entry detected (count increased)"
fi

# Verify the billing entry is linked to a valid encounter
ENCOUNTER_VALID="false"
if [ -n "$BILLING_ENCOUNTER" ] && [ "$BILLING_ENCOUNTER" != "0" ]; then
    ENCOUNTER_CHECK=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID AND encounter='$BILLING_ENCOUNTER'" 2>/dev/null || echo "0")
    if [ "$ENCOUNTER_CHECK" -gt 0 ]; then
        ENCOUNTER_VALID="true"
        echo "Billing entry is linked to valid encounter"
    else
        echo "WARNING: Billing entry encounter does not exist for this patient"
    fi
fi

# Check code type
CODE_TYPE_VALID="false"
if [ "$BILLING_CODE_TYPE" = "CPT4" ] || [ "$BILLING_CODE_TYPE" = "cpt4" ] || [ "$BILLING_CODE_TYPE" = "CPT" ]; then
    CODE_TYPE_VALID="true"
fi

# Check if entry is active
ENTRY_ACTIVE="false"
if [ "$BILLING_ACTIVITY" = "1" ]; then
    ENTRY_ACTIVE="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/fee_sheet_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "expected_encounter": "$PATIENT_ENCOUNTER",
    "expected_code": "$EXPECTED_CODE",
    "initial_billing_count": $INITIAL_BILLING_COUNT,
    "current_billing_count": $CURRENT_BILLING_COUNT,
    "initial_total_billing": $INITIAL_TOTAL_BILLING,
    "current_total_billing": $CURRENT_TOTAL_BILLING,
    "billing_entry_found": $BILLING_FOUND,
    "new_entry_created": $NEW_ENTRY,
    "billing": {
        "id": "$BILLING_ID",
        "date": "$BILLING_DATE",
        "code_type": "$BILLING_CODE_TYPE",
        "code": "$BILLING_CODE",
        "encounter": "$BILLING_ENCOUNTER",
        "fee": "$BILLING_FEE",
        "units": "$BILLING_UNITS",
        "activity": "$BILLING_ACTIVITY",
        "billed": "$BILLING_BILLED"
    },
    "validation": {
        "code_type_valid": $CODE_TYPE_VALID,
        "encounter_linked": $ENCOUNTER_VALID,
        "entry_active": $ENTRY_ACTIVE
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move temp file to final location
rm -f /tmp/fee_sheet_result.json 2>/dev/null || sudo rm -f /tmp/fee_sheet_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fee_sheet_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fee_sheet_result.json
chmod 666 /tmp/fee_sheet_result.json 2>/dev/null || sudo chmod 666 /tmp/fee_sheet_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/fee_sheet_result.json"
cat /tmp/fee_sheet_result.json

echo ""
echo "=== Export Complete ==="