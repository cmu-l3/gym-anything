#!/bin/bash
echo "=== Setting up occupational_manganism_protocol task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find John Zenon ---
JOHN_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND pp.lastname ILIKE '%Zenon%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$JOHN_PATIENT_ID" ]; then
    JOHN_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(pp.name, ' ', COALESCE(pp.lastname,'')) ILIKE '%John%Zenon%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$JOHN_PATIENT_ID" ]; then
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $JOHN_PATIENT_ID"
echo "$JOHN_PATIENT_ID" > /tmp/mang_target_patient_id
chmod 666 /tmp/mang_target_patient_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
echo "Ensuring BLOOD MANGANESE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT 
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'BLOOD MANGANESE LEVEL', 'B_MN', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'B_MN' OR UPPER(name) LIKE '%MANGANESE%'
    );
" 2>/dev/null || true

echo "Ensuring MRI BRAIN test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT 
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'MRI BRAIN WITHOUT CONTRAST', 'MRI_BRAIN', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'MRI_BRAIN' OR UPPER(name) LIKE '%MRI BRAIN%'
    );
" 2>/dev/null || true

# --- 3. Contamination: G21 on Ana Betz (wrong patient) ---
echo "Injecting contamination: G21.2 on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    G21_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'G21%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$G21_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $G21_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $G21_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing G21/T56 and evals for John ---
echo "Cleaning pre-existing G21/T56 records for John..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'G21%' OR code LIKE 'T56%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
echo "Cleaning pre-existing evaluations for John from today..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/mang_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/mang_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/mang_baseline_lab_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/mang_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/mang_baseline_appt_max
for f in /tmp/mang_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/mang_task_start_date
chmod 666 /tmp/mang_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running in Firefox ---
ensure_gnuhealth_logged_in
echo "=== Setup complete ==="