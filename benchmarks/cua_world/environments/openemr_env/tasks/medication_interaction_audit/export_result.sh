#!/bin/bash
source /workspace/scripts/task_utils.sh

PATIENT_PID=$(cat /tmp/task_patient_pid 2>/dev/null | tr -d ' \t\n\r' || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count 2>/dev/null | tr -d ' \t\n\r' || echo "6")
INITIAL_LAB_COUNT=$(cat /tmp/initial_lab_count 2>/dev/null | tr -d ' \t\n\r' || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/medication_audit_final.png" || true

if [ -z "$PATIENT_PID" ] || ! echo "$PATIENT_PID" | grep -qE '^[0-9]+$'; then
    echo '{"error":"patient_pid_not_found","passed":false,"score":0}' > /tmp/medication_audit_result.json
    chmod 666 /tmp/medication_audit_result.json
    exit 0
fi

# --- Query current prescription status ---
q_active() {
    local drug_pattern="$1"
    openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1 AND LOWER(drug) LIKE '${drug_pattern}';" 2>/dev/null | tr -d ' \t\n\r' || echo "0"
}

METFORMIN_ACTIVE=$(q_active '%metformin%')
# NSAIDs: ibuprofen, naproxen, celecoxib, diclofenac, ketorolac
IBUPROFEN_ACTIVE=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1 AND (LOWER(drug) LIKE '%ibuprofen%' OR LOWER(drug) LIKE '%naproxen%' OR LOWER(drug) LIKE '%celecoxib%' OR LOWER(drug) LIKE '%diclofenac%' OR LOWER(drug) LIKE '%ketorolac%');" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NITROFURANTOIN_ACTIVE=$(q_active '%nitrofurantoin%')
AMLODIPINE_ACTIVE=$(q_active '%amlodipine%')
ATORVASTATIN_ACTIVE=$(q_active '%atorvastatin%')
LISINOPRIL_ACTIVE=$(q_active '%lisinopril%')

bool_val() { [ "${1:-0}" -gt "0" ] 2>/dev/null && echo "true" || echo "false"; }

METFORMIN_ACTIVE_BOOL=$(bool_val "$METFORMIN_ACTIVE")
IBUPROFEN_ACTIVE_BOOL=$(bool_val "$IBUPROFEN_ACTIVE")
NITROFURANTOIN_ACTIVE_BOOL=$(bool_val "$NITROFURANTOIN_ACTIVE")
AMLODIPINE_ACTIVE_BOOL=$(bool_val "$AMLODIPINE_ACTIVE")
ATORVASTATIN_ACTIVE_BOOL=$(bool_val "$ATORVASTATIN_ACTIVE")
LISINOPRIL_ACTIVE_BOOL=$(bool_val "$LISINOPRIL_ACTIVE")

# --- Check for new lab/procedure orders ---
LAB_COUNT_AFTER=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_LAB_CONTENT=$(openemr_query "SELECT LOWER(CONCAT_WS(' ', procedure_code, order_diagnosis)) FROM procedure_order WHERE patient_id=${PATIENT_PID} AND UNIX_TIMESTAMP(date_ordered) > ${TASK_START};" 2>/dev/null || echo "")
# Also check orders table
ORDERS_AFTER=$(openemr_query "SELECT COUNT(*) FROM orders WHERE patient_id=${PATIENT_PID} AND UNIX_TIMESTAMP(date_added) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")

LAB_MONITORING="false"
if [ "$LAB_COUNT_AFTER" -gt "$INITIAL_LAB_COUNT" ] 2>/dev/null; then
    LAB_MONITORING="true"
fi
if [ "$ORDERS_AFTER" -gt "0" ] 2>/dev/null; then
    LAB_MONITORING="true"
fi
if echo "$NEW_LAB_CONTENT" | grep -qiE "(bmp|cmp|metabolic|creatinine|urea|bun|urinalysis|urine|renal|kidney|egfr|potassium|electrolyte|chem|panel)"; then
    LAB_MONITORING="true"
fi

# --- Check for new clinical notes ---
NEW_NOTES=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_ENCOUNTERS=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_SOAP=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
NEW_CLINICAL=$(openemr_query "SELECT COUNT(*) FROM form_clinical_notes WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")

NOTE_KEYWORDS="false"
NOTE_BODY=$(openemr_query "SELECT LOWER(body) FROM pnotes WHERE pid=${PATIENT_PID} AND UNIX_TIMESTAMP(date) > ${TASK_START} LIMIT 5;" 2>/dev/null || echo "")
if echo "$NOTE_BODY" | grep -qiE "(medication|reconcil|ckd|kidney|renal|drug|review|discontinu|contraindic)"; then
    NOTE_KEYWORDS="true"
fi

CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1;" 2>/dev/null | tr -d ' \t\n\r' || echo "0")

cat > /tmp/medication_audit_result.json << ENDJSON
{
  "patient_pid": ${PATIENT_PID},
  "task_start": ${TASK_START},
  "initial_rx_count": ${INITIAL_RX_COUNT},
  "current_rx_count": ${CURRENT_RX_COUNT:-0},
  "metformin_still_active": ${METFORMIN_ACTIVE_BOOL},
  "ibuprofen_still_active": ${IBUPROFEN_ACTIVE_BOOL},
  "nitrofurantoin_still_active": ${NITROFURANTOIN_ACTIVE_BOOL},
  "amlodipine_still_active": ${AMLODIPINE_ACTIVE_BOOL},
  "atorvastatin_still_active": ${ATORVASTATIN_ACTIVE_BOOL},
  "lisinopril_still_active": ${LISINOPRIL_ACTIVE_BOOL},
  "initial_lab_count": ${INITIAL_LAB_COUNT},
  "lab_count_after": ${LAB_COUNT_AFTER:-0},
  "new_orders_after_start": ${ORDERS_AFTER:-0},
  "lab_monitoring_ordered": ${LAB_MONITORING},
  "new_pnotes": ${NEW_NOTES:-0},
  "new_encounters": ${NEW_ENCOUNTERS:-0},
  "new_soap_notes": ${NEW_SOAP:-0},
  "new_clinical_notes": ${NEW_CLINICAL:-0},
  "note_has_review_keywords": ${NOTE_KEYWORDS}
}
ENDJSON

chmod 666 /tmp/medication_audit_result.json
echo "Export complete."
cat /tmp/medication_audit_result.json
