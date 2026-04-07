#!/bin/bash
echo "=== Setting up industrial_hexavalent_chromium_exposure task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/chrome_task_start_date
chmod 666 /tmp/task_start_time.txt /tmp/chrome_task_start_date 2>/dev/null || true

# --- 1. Find target patient (Roberto Carlos) ---
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
echo "$ROBERTO_PATIENT_ID" > /tmp/chrome_target_patient_id
chmod 666 /tmp/chrome_target_patient_id 2>/dev/null || true

# --- 2. Ensure T56.2 ICD-10 code exists ---
echo "Ensuring T56.2 pathology code exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology),
        'T56.2', 'Toxic effect of chromium and its compounds', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_pathology WHERE code = 'T56.2'
    );
" 2>/dev/null || true

# --- 3. Ensure required laboratory test types exist ---
for TEST in "HEAVY METAL SCREEN|HEAVY_METAL" "URINALYSIS|URINE" "COMPLETE BLOOD COUNT|CBC" "BASIC METABOLIC PANEL|BMP"; do
    TEST_NAME=$(echo "$TEST" | cut -d'|' -f1)
    TEST_CODE=$(echo "$TEST" | cut -d'|' -f2)
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            '$TEST_NAME', '$TEST_CODE', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_type WHERE code = '$TEST_CODE' OR UPPER(name) LIKE '%$TEST_NAME%'
        );
    " 2>/dev/null || true
done

# --- 4. Contamination injection: T56.2 on Ana Betz (wrong patient) ---
echo "Injecting contamination: T56.2 on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T56_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'T56.2' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T56_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $T56_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $T56_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 5. Clean any pre-existing T-code and evaluation records for Roberto ---
echo "Cleaning pre-existing T-codes for Roberto Carlos..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ROBERTO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for Roberto from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $ROBERTO_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 6. Record baselines ---
echo "Recording baseline state..."
echo $(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]') > /tmp/chrome_baseline_disease_max
echo $(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]') > /tmp/chrome_baseline_eval_max
echo $(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]') > /tmp/chrome_baseline_prescription_max
echo $(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]') > /tmp/chrome_baseline_lab_max
echo $(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]') > /tmp/chrome_baseline_appt_max
for f in /tmp/chrome_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# Take initial screenshot
take_screenshot /tmp/chrome_initial_state.png

echo "=== Setup complete ==="