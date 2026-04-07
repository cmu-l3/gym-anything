#!/bin/bash
echo "=== Setting up chronic_kidney_disease_progression task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Ana Isabel Betz ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Patient Ana Isabel Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Isabel Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/ckd_target_patient_id
chmod 666 /tmp/ckd_target_patient_id 2>/dev/null || true

# Get party_id for lifestyle record check
ANA_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party FROM gnuhealth_patient gp WHERE gp.id = $ANA_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
echo "Ana Isabel Betz party_id: $ANA_PARTY_ID"
echo "$ANA_PARTY_ID" > /tmp/ckd_target_party_id
chmod 666 /tmp/ckd_target_party_id 2>/dev/null || true

# --- 2. Ensure renal lab test types exist ---
echo "Ensuring CREATININE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'SERUM CREATININE', 'CREAT', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CREAT' OR UPPER(name) LIKE '%CREATININE%'
    );
" 2>/dev/null || true

echo "Ensuring BUN lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'BLOOD UREA NITROGEN', 'BUN', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'BUN' OR UPPER(name) LIKE '%BLOOD UREA%' OR UPPER(name) LIKE '%BUN%'
    );
" 2>/dev/null || true

echo "Ensuring ELECTROLYTES lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'SERUM ELECTROLYTES', 'ELEC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'ELEC' OR UPPER(name) LIKE '%ELECTROLYTE%'
    );
" 2>/dev/null || true

echo "Ensuring PHOSPHORUS lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'SERUM PHOSPHORUS', 'PHOS', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'PHOS' OR UPPER(name) LIKE '%PHOSPHORUS%' OR UPPER(name) LIKE '%PHOSPHATE%'
    );
" 2>/dev/null || true

# --- 3. Contamination: N18 CKD diagnosis on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: N18 CKD on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    N18_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'N18' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$N18_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $N18_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $N18_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing N18 CKD records and lifestyle records for Ana ---
echo "Cleaning pre-existing N18 records for Ana..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ANA_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'N18%')
" 2>/dev/null || true

echo "Cleaning pre-existing lifestyle records for Ana..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient_lifestyle = $ANA_PATIENT_ID
" 2>/dev/null || true
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient = $ANA_PATIENT_ID
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

echo "$BASELINE_DISEASE_MAX" > /tmp/ckd_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/ckd_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/ckd_baseline_lab_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/ckd_baseline_lifestyle_max
echo "$BASELINE_APPT_MAX" > /tmp/ckd_baseline_appt_max
for f in /tmp/ckd_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/ckd_task_start_date
chmod 666 /tmp/ckd_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/ckd_initial_state.png

echo "=== chronic_kidney_disease_progression setup complete ==="
echo "Target patient: Ana Isabel Betz (patient_id=$ANA_PATIENT_ID, party_id=$ANA_PARTY_ID)"
echo "Clinical scenario: CKD Stage 3b — nephrology evaluation and management"
echo "IMPORTANT: This is a very_hard task — the agent must independently determine:"
echo "  - Correct ICD-10 code for CKD Stage 3b (N18.3x or N18.4)"
echo "  - Comprehensive renal monitoring panel (creatinine, BUN, electrolytes, phosphorus)"
echo "  - Renoprotective pharmacotherapy (ACE inhibitor or ARB)"
echo "  - Dietary counseling documentation (renal diet, low sodium)"
echo "  - KDIGO-recommended follow-up interval (~3 months for Stage 3b)"
