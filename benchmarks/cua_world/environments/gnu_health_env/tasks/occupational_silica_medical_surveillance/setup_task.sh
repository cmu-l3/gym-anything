#!/bin/bash
echo "=== Setting up occupational_silica_medical_surveillance task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/silica_task_start_date
chmod 666 /tmp/task_start_time.txt /tmp/silica_task_start_date 2>/dev/null || true

# --- 1. Find target patient John Zenon ---
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
echo "$JOHN_PATIENT_ID" > /tmp/silica_target_patient_id
chmod 666 /tmp/silica_target_patient_id 2>/dev/null || true

# --- 2. Ensure baseline lab test types exist ---
echo "Ensuring CBC and CMP lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP');
" 2>/dev/null || true

# --- 3. Inject Contamination (Z57 code on Ana Betz) ---
echo "Injecting contamination: Z57 on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    Z57_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z57%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$Z57_PATHOLOGY_ID" ]; then
        EXISTING_CONTAM=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $Z57_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING_CONTAM:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $Z57_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing records for John Zenon ---
echo "Cleaning pre-existing surveillance records for John Zenon..."
# Remove Z-codes
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z57%')
" 2>/dev/null || true

# Remove recent evaluations
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# Remove lifestyle records
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient = $JOHN_PATIENT_ID OR patient_lifestyle = $JOHN_PATIENT_ID
" 2>/dev/null || true

# Remove future appointments
gnuhealth_db_query "
    DELETE FROM gnuhealth_appointment
    WHERE patient = $JOHN_PATIENT_ID AND appointment_date > CURRENT_DATE
" 2>/dev/null || true

# --- 5. Record Baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/silica_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/silica_baseline_eval_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/silica_baseline_lifestyle_max
echo "$BASELINE_LAB_MAX" > /tmp/silica_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/silica_baseline_appt_max
for f in /tmp/silica_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# --- 6. Configure UI ---
# Ensure GNU Health web interface is running
if ! pgrep -f "trytond" > /dev/null; then
    systemctl start gnuhealth
    sleep 5
fi

# Launch Firefox
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for UI and capture state
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="