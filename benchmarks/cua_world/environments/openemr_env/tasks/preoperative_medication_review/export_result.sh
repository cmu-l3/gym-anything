#!/bin/bash
# Export script for Pre-Operative Medication Review Task
# Queries DB for current state of medications, encounters, vitals, labs, and notes.

echo "=== Exporting Pre-Operative Medication Review Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot "/tmp/preop_review_final.png" || true

# --- Read saved state ---
PATIENT_PID=$(cat /tmp/task_patient_pid 2>/dev/null | tr -d ' \t\n\r' || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")
TASK_START_DATE=$(cat /tmp/task_start_date 2>/dev/null || date +%Y-%m-%d)
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count 2>/dev/null | tr -d ' \t\n\r' || echo "8")
INITIAL_ENC_COUNT=$(cat /tmp/initial_enc_count 2>/dev/null | tr -d ' \t\n\r' || echo "3")
INITIAL_VITALS_COUNT=$(cat /tmp/initial_vitals_count 2>/dev/null | tr -d ' \t\n\r' || echo "0")
INITIAL_LAB_COUNT=$(cat /tmp/initial_lab_count 2>/dev/null | tr -d ' \t\n\r' || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count 2>/dev/null | tr -d ' \t\n\r' || echo "0")

if [ -z "$PATIENT_PID" ] || ! echo "$PATIENT_PID" | grep -qE '^[0-9]+$'; then
    echo '{"error":"patient_pid_not_found","passed":false,"score":0}' > /tmp/preop_review_result.json
    chmod 666 /tmp/preop_review_result.json
    exit 0
fi

# --- Query current medication status ---
q_active() {
    local drug_pattern="$1"
    openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1 AND LOWER(drug) LIKE '${drug_pattern}';" 2>/dev/null | tr -d ' \t\n\r' || echo "0"
}

WARFARIN_ACTIVE=$(q_active '%warfarin%')
CLOPIDOGREL_ACTIVE=$(q_active '%clopidogrel%')
IBUPROFEN_ACTIVE=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1 AND (LOWER(drug) LIKE '%ibuprofen%' OR LOWER(drug) LIKE '%naproxen%' OR LOWER(drug) LIKE '%celecoxib%' OR LOWER(drug) LIKE '%diclofenac%' OR LOWER(drug) LIKE '%ketorolac%');" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
METFORMIN_ACTIVE=$(q_active '%metformin%')
LISINOPRIL_ACTIVE=$(q_active '%lisinopril%')
AMLODIPINE_ACTIVE=$(q_active '%amlodipine%')
ATORVASTATIN_ACTIVE=$(q_active '%atorvastatin%')
OMEPRAZOLE_ACTIVE=$(q_active '%omeprazole%')

bool_val() { [ "${1:-0}" -gt "0" ] 2>/dev/null && echo "true" || echo "false"; }

WARFARIN_BOOL=$(bool_val "$WARFARIN_ACTIVE")
CLOPIDOGREL_BOOL=$(bool_val "$CLOPIDOGREL_ACTIVE")
IBUPROFEN_BOOL=$(bool_val "$IBUPROFEN_ACTIVE")
METFORMIN_BOOL=$(bool_val "$METFORMIN_ACTIVE")
LISINOPRIL_BOOL=$(bool_val "$LISINOPRIL_ACTIVE")
AMLODIPINE_BOOL=$(bool_val "$AMLODIPINE_ACTIVE")
ATORVASTATIN_BOOL=$(bool_val "$ATORVASTATIN_ACTIVE")
OMEPRAZOLE_BOOL=$(bool_val "$OMEPRAZOLE_ACTIVE")

CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1;" 2>/dev/null | tr -d ' \t\n\r' || echo "0")

# --- Query new encounters ---
CURRENT_ENC_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEWEST_ENC=$(openemr_query "SELECT id, date, reason, encounter FROM form_encounter WHERE pid=${PATIENT_PID} ORDER BY id DESC LIMIT 1;" 2>/dev/null)

ENC_FOUND="false"
ENC_DATE=""
ENC_REASON=""
ENC_NUMBER=""
if [ -n "$NEWEST_ENC" ] && [ "$CURRENT_ENC_COUNT" -gt "$INITIAL_ENC_COUNT" ] 2>/dev/null; then
    ENC_FOUND="true"
    ENC_DATE=$(echo "$NEWEST_ENC" | cut -f2)
    ENC_REASON=$(echo "$NEWEST_ENC" | cut -f3 | sed 's/"/\\"/g' | tr '\n' ' ')
    ENC_NUMBER=$(echo "$NEWEST_ENC" | cut -f4)
fi

# --- Query new vitals ---
CURRENT_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals WHERE pid=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEWEST_VITALS=$(openemr_query "SELECT id, date, bps, bpd, pulse, respiration, temperature, oxygen_saturation, weight, height FROM form_vitals WHERE pid=${PATIENT_PID} ORDER BY id DESC LIMIT 1;" 2>/dev/null)

VITALS_FOUND="false"
VITALS_BPS=""
VITALS_BPD=""
VITALS_PULSE=""
VITALS_RESP=""
VITALS_TEMP=""
VITALS_O2=""
VITALS_WEIGHT=""
VITALS_HEIGHT=""
if [ -n "$NEWEST_VITALS" ] && [ "$CURRENT_VITALS_COUNT" -gt "$INITIAL_VITALS_COUNT" ] 2>/dev/null; then
    VITALS_FOUND="true"
    VITALS_BPS=$(echo "$NEWEST_VITALS" | cut -f3)
    VITALS_BPD=$(echo "$NEWEST_VITALS" | cut -f4)
    VITALS_PULSE=$(echo "$NEWEST_VITALS" | cut -f5)
    VITALS_RESP=$(echo "$NEWEST_VITALS" | cut -f6)
    VITALS_TEMP=$(echo "$NEWEST_VITALS" | cut -f7)
    VITALS_O2=$(echo "$NEWEST_VITALS" | cut -f8)
    VITALS_WEIGHT=$(echo "$NEWEST_VITALS" | cut -f9)
    VITALS_HEIGHT=$(echo "$NEWEST_VITALS" | cut -f10)
fi

# --- Query new lab/procedure orders ---
LAB_COUNT_AFTER=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
ORDERS_AFTER=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=${PATIENT_PID} AND UNIX_TIMESTAMP(date_ordered) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")

LAB_ORDERED="false"
if [ "$LAB_COUNT_AFTER" -gt "$INITIAL_LAB_COUNT" ] 2>/dev/null; then
    LAB_ORDERED="true"
fi
if [ "$ORDERS_AFTER" -gt "0" ] 2>/dev/null; then
    LAB_ORDERED="true"
fi

# --- Query new clinical notes ---
NEW_PNOTES=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_ENCOUNTERS=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_SOAP=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_CLINICAL=$(openemr_query "SELECT COUNT(*) FROM form_clinical_notes WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")

# --- Check encounter date matches today ---
ENC_DATE_TODAY="false"
if [ -n "$ENC_DATE" ]; then
    ENC_DATE_SHORT=$(echo "$ENC_DATE" | cut -d' ' -f1)
    if [ "$ENC_DATE_SHORT" = "$TASK_START_DATE" ]; then
        ENC_DATE_TODAY="true"
    fi
fi

# --- Write result JSON ---
cat > /tmp/preop_review_result.json << ENDJSON
{
  "patient_pid": ${PATIENT_PID},
  "task_start": ${TASK_START},
  "initial_rx_count": ${INITIAL_RX_COUNT},
  "current_rx_count": ${CURRENT_RX_COUNT:-0},
  "warfarin_still_active": ${WARFARIN_BOOL},
  "clopidogrel_still_active": ${CLOPIDOGREL_BOOL},
  "ibuprofen_still_active": ${IBUPROFEN_BOOL},
  "metformin_still_active": ${METFORMIN_BOOL},
  "lisinopril_still_active": ${LISINOPRIL_BOOL},
  "amlodipine_still_active": ${AMLODIPINE_BOOL},
  "atorvastatin_still_active": ${ATORVASTATIN_BOOL},
  "omeprazole_still_active": ${OMEPRAZOLE_BOOL},
  "initial_enc_count": ${INITIAL_ENC_COUNT},
  "current_enc_count": ${CURRENT_ENC_COUNT:-0},
  "encounter_found": ${ENC_FOUND},
  "encounter_date": "${ENC_DATE}",
  "encounter_date_today": ${ENC_DATE_TODAY},
  "encounter_reason": "${ENC_REASON}",
  "initial_vitals_count": ${INITIAL_VITALS_COUNT},
  "current_vitals_count": ${CURRENT_VITALS_COUNT:-0},
  "vitals_found": ${VITALS_FOUND},
  "vitals_bps": "${VITALS_BPS}",
  "vitals_bpd": "${VITALS_BPD}",
  "vitals_pulse": "${VITALS_PULSE}",
  "vitals_respiration": "${VITALS_RESP}",
  "vitals_temperature": "${VITALS_TEMP}",
  "vitals_oxygen_saturation": "${VITALS_O2}",
  "vitals_weight": "${VITALS_WEIGHT}",
  "vitals_height": "${VITALS_HEIGHT}",
  "initial_lab_count": ${INITIAL_LAB_COUNT},
  "lab_count_after": ${LAB_COUNT_AFTER:-0},
  "new_orders_after_start": ${ORDERS_AFTER:-0},
  "lab_ordered": ${LAB_ORDERED},
  "new_pnotes": ${NEW_PNOTES:-0},
  "new_encounters": ${NEW_ENCOUNTERS:-0},
  "new_soap_notes": ${NEW_SOAP:-0},
  "new_clinical_notes": ${NEW_CLINICAL:-0},
  "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/preop_review_result.json
echo ""
echo "Export complete."
cat /tmp/preop_review_result.json
echo ""
echo "=== Export Complete ==="
