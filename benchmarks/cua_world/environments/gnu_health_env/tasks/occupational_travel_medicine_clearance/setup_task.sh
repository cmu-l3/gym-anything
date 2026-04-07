#!/bin/bash
echo "=== Setting up occupational_travel_medicine_clearance task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/travel_target_patient_id
chmod 666 /tmp/travel_target_patient_id 2>/dev/null || true

# Get party_id for additional checks
JOHN_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party FROM gnuhealth_patient gp WHERE gp.id = $JOHN_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
echo "$JOHN_PARTY_ID" > /tmp/travel_target_party_id
chmod 666 /tmp/travel_target_party_id 2>/dev/null || true

# --- 2. Contamination: Z29 condition on Ana Betz (wrong patient distractor) ---
echo "Injecting contamination: Z29 diagnosis on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    Z29_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z29%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$Z29_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $Z29_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $Z29_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 3. Clean pre-existing task-specific records for John Zenon ---
echo "Cleaning pre-existing Z-code records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z29%' OR code LIKE 'Z02%')
" 2>/dev/null || true

echo "Cleaning pre-existing clinical evaluations for John Zenon from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

echo "Cleaning future appointments for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_appointment
    WHERE patient = $JOHN_PATIENT_ID
      AND appointment_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 4. Record baselines for verification ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_VAX_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_vaccination" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/travel_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/travel_baseline_eval_max
echo "$BASELINE_VAX_MAX" > /tmp/travel_baseline_vax_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/travel_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/travel_baseline_appt_max
for f in /tmp/travel_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/travel_task_start_date
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/travel_task_start_date /tmp/task_start_time.txt 2>/dev/null || true

# --- 5. Prepare GNU Health interface ---
echo "Ensuring GNU Health is running..."
systemctl start gnuhealth || true
ensure_gnuhealth_logged_in "http://localhost:8000/"

# Maximize browser window to ensure visibility
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/travel_initial_state.png

echo "=== Setup complete ==="