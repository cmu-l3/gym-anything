#!/bin/bash
echo "=== Setting up agricultural_pesticide_poisoning_protocol task ==="

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
echo "$ROBERTO_PATIENT_ID" > /tmp/pest_target_patient_id
chmod 666 /tmp/pest_target_patient_id 2>/dev/null || true

# --- 2. Remove any pre-existing Cholinesterase lab or Atropine medicament ---
echo "Cleaning pre-existing custom labs or drugs..."
# Remove Cholinesterase Lab Test Type if it exists
CHOLIN_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_lab_test_type WHERE code = 'CHOLIN' OR UPPER(name) LIKE '%CHOLINESTERASE%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$CHOLIN_ID" ]; then
    gnuhealth_db_query "DELETE FROM gnuhealth_patient_lab_test WHERE test_type = $CHOLIN_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_lab_test_critearea WHERE test_type_id = $CHOLIN_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_lab_test_type WHERE id = $CHOLIN_ID" 2>/dev/null || true
fi

# Remove Atropine Medicament if it exists
ATROPINE_ID=$(gnuhealth_db_query "
    SELECT m.id FROM gnuhealth_medicament m 
    JOIN product_product pp ON m.name = pp.id 
    JOIN product_template pt ON pp.template = pt.id 
    WHERE UPPER(pt.name) LIKE '%ATROPINE%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$ATROPINE_ID" ]; then
    gnuhealth_db_query "DELETE FROM gnuhealth_prescription_order_line WHERE medicament = $ATROPINE_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_medicament WHERE id = $ATROPINE_ID" 2>/dev/null || true
fi

# --- 3. Contamination: T60 exposure on Luna (wrong patient) ---
echo "Injecting contamination: T60 exposure on Luna..."
LUNA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Luna%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$LUNA_PATIENT_ID" ]; then
    T60_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T60%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T60_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $LUNA_PATIENT_ID AND pathology = $T60_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $LUNA_PATIENT_ID, $T60_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing T60 or evaluation records for Roberto ---
echo "Cleaning pre-existing T60 disease records for Roberto Carlos..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease 
    WHERE patient = $ROBERTO_PATIENT_ID 
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T60%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
echo "Cleaning pre-existing evaluations for Roberto from today..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $ROBERTO_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')
BASELINE_LAB_TYPE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_lab_test_type" | tr -d '[:space:]')
BASELINE_MEDICAMENT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_medicament" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/pest_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/pest_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/pest_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/pest_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/pest_baseline_appt_max
echo "$BASELINE_LAB_TYPE_MAX" > /tmp/pest_baseline_lab_type_max
echo "$BASELINE_MEDICAMENT_MAX" > /tmp/pest_baseline_medicament_max

for f in /tmp/pest_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%s > /tmp/task_start_time
chmod 666 /tmp/task_start_time 2>/dev/null || true

# --- 6. Ensure GNU Health is running and UI is ready ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

# Take initial screenshot
take_screenshot /tmp/pest_initial_state.png

echo "=== Task setup complete ==="