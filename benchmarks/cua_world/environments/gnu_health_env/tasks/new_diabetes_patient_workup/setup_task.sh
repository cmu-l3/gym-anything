#!/bin/bash
echo "=== Setting up new_diabetes_patient_workup task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Verify Bonifacio Caput exists ---
BONIFACIO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Bonifacio%' AND pp.lastname ILIKE '%Caput%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$BONIFACIO_PATIENT_ID" ]; then
    echo "FATAL: Patient Bonifacio Caput not found in demo database. Aborting."
    exit 1
fi
echo "Bonifacio Caput patient_id: $BONIFACIO_PATIENT_ID"
echo "$BONIFACIO_PATIENT_ID" > /tmp/dm_target_patient_id
chmod 666 /tmp/dm_target_patient_id 2>/dev/null || true

# --- 2. Clean pre-existing E11 disease record for Bonifacio (idempotency) ---
echo "Cleaning pre-existing E11 record for Bonifacio Caput..."
PATHOLOGY_E11_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_pathology WHERE code = 'E11' LIMIT 1" | tr -d '[:space:]')
echo "ICD-10 E11 pathology_id: ${PATHOLOGY_E11_ID:-not_found}"
if [ -n "$PATHOLOGY_E11_ID" ] && [ -n "$BONIFACIO_PATIENT_ID" ]; then
    gnuhealth_db_query "
        DELETE FROM gnuhealth_patient_disease
        WHERE patient = $BONIFACIO_PATIENT_ID AND pathology = $PATHOLOGY_E11_ID
    " 2>/dev/null || true
fi

# --- 3. Clean any pre-existing Penicillin allergy for Bonifacio ---
echo "Cleaning pre-existing Penicillin allergy for Bonifacio Caput..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_allergy
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND LOWER(allergen) LIKE '%penicillin%'
" 2>/dev/null || true

# --- 4. Clean any pre-existing HbA1c lab order for Bonifacio ---
echo "Cleaning pre-existing HbA1c lab for Bonifacio Caput..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lab_test
    WHERE patient_id = $BONIFACIO_PATIENT_ID
      AND test_type IN (
          SELECT id FROM gnuhealth_lab_test_type
          WHERE code = 'HBA1C' OR UPPER(name) LIKE '%HBA1C%' OR UPPER(name) LIKE '%GLYCATED%'
      )
" 2>/dev/null || true

# --- 5. Verify HbA1c lab test type exists (should be added by setup_gnuhealth.sh) ---
HBAC_TYPE=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_lab_test_type
    WHERE code = 'HBA1C' OR UPPER(name) LIKE '%HBA1C%' OR UPPER(name) LIKE '%GLYCATED%'
    LIMIT 1" | tr -d '[:space:]')
echo "HbA1c lab type id: ${HBAC_TYPE:-missing}"
if [ -z "$HBAC_TYPE" ]; then
    echo "WARNING: HbA1c lab type not found. Adding it now..."
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            'GLYCATED HEMOGLOBIN (HbA1c)', 'HBA1C', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HBA1C');
    " 2>/dev/null || true
fi

# --- 6. Record baseline counts (max IDs before task) ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_ALLERGY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_allergy" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline allergy max: $BASELINE_ALLERGY_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/dm_baseline_disease_max
echo "$BASELINE_ALLERGY_MAX" > /tmp/dm_baseline_allergy_max
echo "$BASELINE_LAB_MAX" > /tmp/dm_baseline_lab_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/dm_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/dm_baseline_appt_max
for f in /tmp/dm_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/dm_task_start_date
chmod 666 /tmp/dm_task_start_date 2>/dev/null || true

# --- 7. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# --- 8. Login ---
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# --- 9. Screenshot ---
take_screenshot /tmp/dm_initial_state.png

echo "=== new_diabetes_patient_workup setup complete ==="
echo "Target patient: Bonifacio Caput (patient_id=$BONIFACIO_PATIENT_ID)"
echo "Tasks to complete:"
echo "  1. Add Type 2 Diabetes Mellitus condition (ICD-10: E11)"
echo "  2. Document Penicillin allergy (severity: Severe, reaction: Anaphylaxis)"
echo "  3. Order HbA1c (GLYCATED HEMOGLOBIN) lab test"
echo "  4. Prescribe Metformin (Dr. Cordara)"
echo "  5. Schedule follow-up in 35-60 days (Dr. Cordara)"
