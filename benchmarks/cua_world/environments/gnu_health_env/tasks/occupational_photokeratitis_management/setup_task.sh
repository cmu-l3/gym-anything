#!/bin/bash
echo "=== Setting up occupational_photokeratitis_management task ==="

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
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $JOHN_PATIENT_ID"
echo "$JOHN_PATIENT_ID" > /tmp/photo_target_patient_id
chmod 666 /tmp/photo_target_patient_id 2>/dev/null || true

# Get party_id for name lookup in verifier
JOHN_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party FROM gnuhealth_patient gp WHERE gp.id = $JOHN_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
JOHN_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(name, ' ', COALESCE(lastname,'')) FROM party_party WHERE id = $JOHN_PARTY_ID LIMIT 1" | sed 's/^[[:space:]]*//')
echo "$JOHN_NAME" > /tmp/photo_target_patient_name
chmod 666 /tmp/photo_target_patient_name 2>/dev/null || true

# --- 2. Contamination: H16.1 photokeratitis on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: H16 on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    H16_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'H16%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$H16_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $H16_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $H16_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 3. Clean pre-existing H-codes, T-codes, and evaluations for John ---
echo "Cleaning pre-existing H16/T26 disease records for John..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'H16%' OR code LIKE 'T26%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for John from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 4. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/photo_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/photo_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/photo_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/photo_baseline_appt_max
for f in /tmp/photo_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/photo_task_start_date
chmod 666 /tmp/photo_task_start_date 2>/dev/null || true

# --- 5. Ensure GNU Health is running and log in ---
echo "Ensuring GNU Health is logged in..."
ensure_gnuhealth_logged_in "http://localhost:8000/#"

# Wait a moment for UI to settle
sleep 3
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="