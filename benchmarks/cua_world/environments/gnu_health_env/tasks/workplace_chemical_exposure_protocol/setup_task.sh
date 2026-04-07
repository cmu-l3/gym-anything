#!/bin/bash
echo "=== Setting up workplace_chemical_exposure_protocol task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Bonifacio Caput ---
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
echo "$BONIFACIO_PATIENT_ID" > /tmp/occ_target_patient_id
chmod 666 /tmp/occ_target_patient_id 2>/dev/null || true

# --- 2. Ensure toxicology lab test type exists ---
echo "Ensuring TOXICOLOGY SCREEN lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'TOXICOLOGY SCREEN', 'TOX_SCREEN', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'TOX_SCREEN' OR UPPER(name) LIKE '%TOXICOLOGY%'
    );
" 2>/dev/null || true

echo "Ensuring CBC lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

echo "Ensuring BMP lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'BASIC METABOLIC PANEL', 'BMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'BMP' OR UPPER(name) LIKE '%BASIC METABOLIC%'
    );
" 2>/dev/null || true

# --- 3. Contamination: T-code burn on Ana Betz (wrong patient) ---
echo "Injecting contamination: T20 burn on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T20_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T20%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T20_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $T20_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $T20_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing T-code records and evaluations for Bonifacio ---
echo "Cleaning pre-existing T-code disease records for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for Bonifacio from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/occ_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/occ_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/occ_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/occ_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/occ_baseline_appt_max
for f in /tmp/occ_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/occ_task_start_date
chmod 666 /tmp/occ_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/occ_initial_state.png

echo "=== workplace_chemical_exposure_protocol setup complete ==="
echo "Target patient: Bonifacio Caput (patient_id=$BONIFACIO_PATIENT_ID)"
echo "Clinical scenario: Chemical splash burn — occupational injury documentation"
echo "IMPORTANT: This is a very_hard task — the agent must independently determine:"
echo "  - Appropriate ICD-10 T-code for chemical burn (T54.x or T20-T32)"
echo "  - Clinical evaluation with injury findings"
echo "  - Wound care treatment (silver sulfadiazine, bacitracin, etc.)"
echo "  - Toxicology and baseline laboratory orders"
echo "  - Wound reassessment timing (3-10 days)"
