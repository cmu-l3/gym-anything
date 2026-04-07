#!/bin/bash
echo "=== Setting up acs_secondary_prevention task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Roberto Carlos ---
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ROBERTO_PATIENT_ID" ]; then
    echo "FATAL: Patient Roberto Carlos not found in demo database. Aborting."
    exit 1
fi
echo "Roberto Carlos patient_id: $ROBERTO_PATIENT_ID"
echo "$ROBERTO_PATIENT_ID" > /tmp/acs_target_patient_id
chmod 666 /tmp/acs_target_patient_id 2>/dev/null || true

# --- 2. Ensure lipid lab test types exist ---
echo "Ensuring Lipid Panel test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'LIPID PANEL', 'LIPID', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'LIPID' OR UPPER(name) LIKE '%LIPID%'
    );
" 2>/dev/null || true

echo "Ensuring Cholesterol lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'TOTAL CHOLESTEROL', 'CHOL', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CHOL' OR UPPER(name) LIKE '%CHOLESTEROL%'
    );
" 2>/dev/null || true

echo "Ensuring LDL lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'LDL CHOLESTEROL', 'LDL', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'LDL' OR UPPER(name) LIKE '%LDL%'
    );
" 2>/dev/null || true

# --- 3. Contamination: I21 diagnosis on Ana Betz (wrong patient) ---
echo "Injecting contamination: I21 Acute MI on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    I21_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'I21' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$I21_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $I21_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $I21_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing I21/I25 diagnoses and lifestyle records for Roberto ---
echo "Cleaning pre-existing cardiac disease records for Roberto Carlos..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ROBERTO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'I21%' OR code LIKE 'I25%')
" 2>/dev/null || true

echo "Cleaning pre-existing lifestyle records for Roberto Carlos..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient_lifestyle = $ROBERTO_PATIENT_ID OR patient = $ROBERTO_PATIENT_ID
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline lifestyle max: $BASELINE_LIFESTYLE_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/acs_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/acs_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/acs_baseline_lab_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/acs_baseline_lifestyle_max
echo "$BASELINE_APPT_MAX" > /tmp/acs_baseline_appt_max
for f in /tmp/acs_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/acs_task_start_date
chmod 666 /tmp/acs_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running in Firefox ---
ensure_firefox_gnuhealth
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="