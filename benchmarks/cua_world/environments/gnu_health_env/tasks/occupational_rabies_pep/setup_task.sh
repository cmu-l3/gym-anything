#!/bin/bash
echo "=== Setting up occupational_rabies_pep task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find target patient (John Zenon) ---
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
echo "$JOHN_PATIENT_ID" > /tmp/rabies_target_patient_id
chmod 666 /tmp/rabies_target_patient_id 2>/dev/null || true

# --- 2. Ensure Pathology Codes exist (W54, Z20.3) ---
echo "Ensuring required ICD-10 codes exist in database..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology), 'W54', 'Bitten or struck by dog', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code LIKE 'W54%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology), 'Z20.3', 'Contact with and (suspected) exposure to rabies', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code LIKE 'Z20.3%');
" 2>/dev/null || true

# --- 3. Contamination: Inject W54 and Tetanus on Roberto Carlos ---
echo "Injecting contamination on Roberto Carlos (wrong patient)..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    W54_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code LIKE 'W54%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$W54_ID" ]; then
        EXISTING=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $W54_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease), $ROBERTO_PATIENT_ID, $W54_ID, true, 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing task-related data for John Zenon ---
echo "Cleaning existing task-related data for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'W54%' OR code LIKE 'Z20%')
" 2>/dev/null || true

gnuhealth_db_query "
    DELETE FROM gnuhealth_appointment
    WHERE patient = $JOHN_PATIENT_ID
      AND appointment_date > NOW()
" 2>/dev/null || true

# --- 5. Record Baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_VACCINATION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_vaccination" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/rabies_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/rabies_baseline_prescription_max
echo "$BASELINE_VACCINATION_MAX" > /tmp/rabies_baseline_vaccination_max
echo "$BASELINE_APPT_MAX" > /tmp/rabies_baseline_appt_max
for f in /tmp/rabies_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/rabies_task_start_date
chmod 666 /tmp/rabies_task_start_date 2>/dev/null || true

# --- 6. Prepare UI ---
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"
    sleep 5
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take setup screenshot
sleep 2
take_screenshot /tmp/task_setup_state.png

echo "=== Setup complete ==="