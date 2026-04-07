#!/bin/bash
# Export script for Document Encounter Task

echo "=== Exporting Document Encounter Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=9

# Get initial counts
INITIAL_ENC_COUNT=$(cat /tmp/initial_enc_count 2>/dev/null || echo "0")
INITIAL_VITALS_COUNT=$(cat /tmp/initial_vitals_count 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/task_start_date 2>/dev/null || date +%Y-%m-%d)

# Get current counts
CURRENT_ENC_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Encounter count: initial=$INITIAL_ENC_COUNT, current=$CURRENT_ENC_COUNT"
echo "Vitals count: initial=$INITIAL_VITALS_COUNT, current=$CURRENT_VITALS_COUNT"

# Query for the most recent encounter
echo ""
echo "=== Querying encounters for patient PID=$PATIENT_PID ==="
ALL_ENC=$(openemr_query "SELECT id, date, reason, encounter, pid FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent encounters:"
echo "$ALL_ENC"

# Get the newest encounter
NEWEST_ENC=$(openemr_query "SELECT id, date, reason, encounter, pid FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse encounter data
ENC_FOUND="false"
ENC_ID=""
ENC_DATE=""
ENC_REASON=""
ENC_NUMBER=""

if [ -n "$NEWEST_ENC" ] && [ "$CURRENT_ENC_COUNT" -gt "$INITIAL_ENC_COUNT" ]; then
    ENC_FOUND="true"
    ENC_ID=$(echo "$NEWEST_ENC" | cut -f1)
    ENC_DATE=$(echo "$NEWEST_ENC" | cut -f2)
    ENC_REASON=$(echo "$NEWEST_ENC" | cut -f3)
    ENC_NUMBER=$(echo "$NEWEST_ENC" | cut -f4)

    echo ""
    echo "New encounter found:"
    echo "  ID: $ENC_ID"
    echo "  Date: $ENC_DATE"
    echo "  Reason: $ENC_REASON"
    echo "  Encounter Number: $ENC_NUMBER"
fi

# Query for vitals linked to this encounter or recent vitals
echo ""
echo "=== Querying vitals for patient PID=$PATIENT_PID ==="
ALL_VITALS=$(openemr_query "SELECT id, date, bps, bpd, pulse, respiration, temperature, oxygen_saturation FROM form_vitals WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent vitals:"
echo "$ALL_VITALS"

# Get the newest vitals
NEWEST_VITALS=$(openemr_query "SELECT id, date, bps, bpd, pulse, respiration, temperature, oxygen_saturation, weight, height FROM form_vitals WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse vitals data
VITALS_FOUND="false"
VITALS_ID=""
VITALS_DATE=""
VITALS_BPS=""
VITALS_BPD=""
VITALS_PULSE=""
VITALS_RESP=""
VITALS_TEMP=""
VITALS_O2=""

if [ -n "$NEWEST_VITALS" ] && [ "$CURRENT_VITALS_COUNT" -gt "$INITIAL_VITALS_COUNT" ]; then
    VITALS_FOUND="true"
    VITALS_ID=$(echo "$NEWEST_VITALS" | cut -f1)
    VITALS_DATE=$(echo "$NEWEST_VITALS" | cut -f2)
    VITALS_BPS=$(echo "$NEWEST_VITALS" | cut -f3)
    VITALS_BPD=$(echo "$NEWEST_VITALS" | cut -f4)
    VITALS_PULSE=$(echo "$NEWEST_VITALS" | cut -f5)
    VITALS_RESP=$(echo "$NEWEST_VITALS" | cut -f6)
    VITALS_TEMP=$(echo "$NEWEST_VITALS" | cut -f7)
    VITALS_O2=$(echo "$NEWEST_VITALS" | cut -f8)

    echo ""
    echo "New vitals found:"
    echo "  ID: $VITALS_ID"
    echo "  BP: $VITALS_BPS/$VITALS_BPD"
    echo "  Pulse: $VITALS_PULSE"
    echo "  Resp: $VITALS_RESP"
    echo "  Temp: $VITALS_TEMP"
    echo "  O2: $VITALS_O2"
fi

# Check for diagnosis - look in billing table and lists table
echo ""
echo "=== Checking for diagnosis ==="

# Check billing table for ICD-10 codes
BILLING_DX=""
if [ -n "$ENC_NUMBER" ]; then
    BILLING_DX=$(openemr_query "SELECT id, code, code_text FROM billing WHERE pid=$PATIENT_PID AND encounter='$ENC_NUMBER' AND code_type='ICD10' ORDER BY id DESC LIMIT 5" 2>/dev/null)
fi

# Also check lists table for new medical problems
LISTS_DX=$(openemr_query "SELECT id, title, diagnosis, begdate FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%respiratory%' OR title LIKE '%URI%' OR title LIKE '%infection%' OR diagnosis LIKE '%J06%') ORDER BY id DESC LIMIT 5" 2>/dev/null)

echo "Billing diagnoses: $BILLING_DX"
echo "Lists diagnoses: $LISTS_DX"

# Parse diagnosis
DX_FOUND="false"
DX_CODE=""
DX_TEXT=""
DX_HAS_J06="false"
DX_HAS_URI="false"

if [ -n "$BILLING_DX" ]; then
    DX_FOUND="true"
    DX_CODE=$(echo "$BILLING_DX" | head -1 | cut -f2)
    DX_TEXT=$(echo "$BILLING_DX" | head -1 | cut -f3)
elif [ -n "$LISTS_DX" ]; then
    DX_FOUND="true"
    DX_CODE=$(echo "$LISTS_DX" | head -1 | cut -f3)
    DX_TEXT=$(echo "$LISTS_DX" | head -1 | cut -f2)
fi

# Check for J06.9 or URI-related diagnosis
COMBINED_DX="$DX_CODE $DX_TEXT $BILLING_DX $LISTS_DX"
if echo "$COMBINED_DX" | grep -qi "J06"; then
    DX_HAS_J06="true"
fi
if echo "$COMBINED_DX" | grep -qi "respiratory\|URI\|infection"; then
    DX_HAS_URI="true"
fi

echo "Diagnosis found: $DX_FOUND (J06: $DX_HAS_J06, URI: $DX_HAS_URI)"

# Validate vitals are in expected range
BP_VALID="false"
if [ -n "$VITALS_BPS" ] && [ -n "$VITALS_BPD" ]; then
    BPS_INT=${VITALS_BPS%%.*}
    BPD_INT=${VITALS_BPD%%.*}
    if [ "$BPS_INT" -ge 100 ] 2>/dev/null && [ "$BPS_INT" -le 140 ] 2>/dev/null && \
       [ "$BPD_INT" -ge 60 ] 2>/dev/null && [ "$BPD_INT" -le 90 ] 2>/dev/null; then
        BP_VALID="true"
    fi
fi

TEMP_VALID="false"
if [ -n "$VITALS_TEMP" ]; then
    # Temperature should be around 99.1 (98-100 range)
    TEMP_INT=${VITALS_TEMP%%.*}
    if [ "$TEMP_INT" -ge 97 ] 2>/dev/null && [ "$TEMP_INT" -le 101 ] 2>/dev/null; then
        TEMP_VALID="true"
    fi
fi

# Escape special characters
ENC_REASON_ESCAPED=$(echo "$ENC_REASON" | sed 's/"/\\"/g' | tr '\n' ' ')
DX_TEXT_ESCAPED=$(echo "$DX_TEXT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/encounter_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_enc_count": ${INITIAL_ENC_COUNT:-0},
    "current_enc_count": ${CURRENT_ENC_COUNT:-0},
    "initial_vitals_count": ${INITIAL_VITALS_COUNT:-0},
    "current_vitals_count": ${CURRENT_VITALS_COUNT:-0},
    "encounter_found": $ENC_FOUND,
    "encounter": {
        "id": "$ENC_ID",
        "date": "$ENC_DATE",
        "reason": "$ENC_REASON_ESCAPED",
        "encounter_number": "$ENC_NUMBER"
    },
    "vitals_found": $VITALS_FOUND,
    "vitals": {
        "id": "$VITALS_ID",
        "bp_systolic": "${VITALS_BPS:-}",
        "bp_diastolic": "${VITALS_BPD:-}",
        "pulse": "${VITALS_PULSE:-}",
        "respiratory_rate": "${VITALS_RESP:-}",
        "temperature": "${VITALS_TEMP:-}",
        "oxygen_saturation": "${VITALS_O2:-}"
    },
    "diagnosis_found": $DX_FOUND,
    "diagnosis": {
        "code": "$DX_CODE",
        "text": "$DX_TEXT_ESCAPED",
        "has_j06": $DX_HAS_J06,
        "has_uri_text": $DX_HAS_URI
    },
    "validation": {
        "bp_in_range": $BP_VALID,
        "temp_in_range": $TEMP_VALID,
        "encounter_date_today": $([ "$ENC_DATE" = "$TASK_START_DATE" ] && echo "true" || echo "false")
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/document_encounter_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_encounter_result.json
chmod 666 /tmp/document_encounter_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/document_encounter_result.json"
cat /tmp/document_encounter_result.json

echo ""
echo "=== Export Complete ==="
