#!/bin/bash
echo "=== Setting up document_workplace_fatality task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start
date +%s > /tmp/fatality_task_start_time.txt

# --- 1. Find target patient Bonifacio Caput ---
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
echo "$BONIFACIO_PATIENT_ID" > /tmp/fatality_target_patient_id
chmod 666 /tmp/fatality_target_patient_id 2>/dev/null || true

# --- 2. Ensure required ICD-10 codes exist (T59 and J96) ---
echo "Verifying T59.x and J96.x exist in pathology database..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology), 'T59.6', 'Toxic effect of hydrogen sulfide', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code LIKE 'T59%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology), 'J96.0', 'Acute respiratory failure', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code LIKE 'J96%');
" 2>/dev/null || true

# --- 3. Clean and reset Bonifacio's records ---
echo "Resetting Bonifacio Caput's clinical state..."
gnuhealth_db_query "
    UPDATE gnuhealth_patient 
    SET deceased = False, dod = NULL, cod = NULL 
    WHERE id = $BONIFACIO_PATIENT_ID
" 2>/dev/null || true

gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease 
    WHERE patient = $BONIFACIO_PATIENT_ID 
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T59%' OR code LIKE 'J96%' OR code LIKE 'J68%' OR code LIKE 'J80%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation 
    WHERE patient = $BONIFACIO_PATIENT_ID 
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 4. Contamination: Inject T59 on a distractor patient (Ana Betz) ---
echo "Injecting contamination: T59 exposure on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    T59_PATHOLOGY_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T59%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T59_PATHOLOGY_ID" ]; then
        EXISTING_CONTAM=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $ANA_PATIENT_ID AND pathology = $T59_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING_CONTAM:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $T59_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 5. Record Baseline IDs for Anti-Gaming ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/fatality_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/fatality_baseline_eval_max
date +%Y-%m-%d > /tmp/fatality_task_start_date

for f in /tmp/fatality_*; do chmod 666 "$f" 2>/dev/null || true; done

# --- 6. Prepare UI / Application State ---
echo "Ensuring GNU Health is running..."
ensure_gnuhealth_logged_in

echo "Capturing initial screenshot..."
sleep 2
take_screenshot /tmp/fatality_initial_state.png

echo "=== Task setup complete ==="