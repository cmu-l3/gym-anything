#!/bin/bash
echo "=== Setting up configure_lead_monitoring_panel task ==="

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
echo "$BONIFACIO_PATIENT_ID" > /tmp/lead_target_patient_id
chmod 666 /tmp/lead_target_patient_id 2>/dev/null || true

# --- 2. Distractor: General blood panel for Ana Betz ---
echo "Injecting distractor: General Blood Panel for Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    gnuhealth_db_query "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'GENERAL BLOOD PANEL', 'GEN_BLOOD', true, 1, NOW(), 1, NOW()
        WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'GEN_BLOOD');
    " 2>/dev/null || true
    
    GEN_BLOOD_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_lab_test_type WHERE code = 'GEN_BLOOD' LIMIT 1" | tr -d '[:space:]')
    
    if [ -n "$GEN_BLOOD_ID" ]; then
        EXISTING_LAB=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_lab_test WHERE patient_id = $ANA_PATIENT_ID AND test_type = $GEN_BLOOD_ID" | tr -d '[:space:]')
        if [ "${EXISTING_LAB:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_lab_test (id, patient_id, test_type, state, date, create_uid, create_date, write_uid, write_date)
                VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_lab_test), $ANA_PATIENT_ID, $GEN_BLOOD_ID, 'draft', NOW(), 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        fi
    fi
fi

# --- 3. Clean up any existing LEAD_OCC test type and its records ---
echo "Cleaning pre-existing LEAD_OCC records..."
LEAD_OCC_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_lab_test_type WHERE code = 'LEAD_OCC'" | tr -d '[:space:]')
if [ -n "$LEAD_OCC_ID" ]; then
    gnuhealth_db_query "DELETE FROM gnuhealth_patient_lab_test WHERE test_type = $LEAD_OCC_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_lab_test_critearea WHERE test_type_id = $LEAD_OCC_ID" 2>/dev/null || true
    gnuhealth_db_query "DELETE FROM gnuhealth_lab_test_type WHERE id = $LEAD_OCC_ID" 2>/dev/null || true
fi

# Clean up any new appointments for Bonifacio Caput
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_appointment
    WHERE patient = $BONIFACIO_PATIENT_ID AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 4. Record baselines ---
echo "Recording baseline state..."
BASELINE_LAB_TYPE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_lab_test_type" | tr -d '[:space:]')
BASELINE_CRITERIA_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_lab_test_critearea" | tr -d '[:space:]')
BASELINE_LAB_REQ_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline lab_test_type max: $BASELINE_LAB_TYPE_MAX"
echo "Baseline lab criteria max: $BASELINE_CRITERIA_MAX"
echo "Baseline lab requests max: $BASELINE_LAB_REQ_MAX"
echo "Baseline appointments max: $BASELINE_APPT_MAX"

echo "$BASELINE_LAB_TYPE_MAX" > /tmp/lead_baseline_lab_type_max
echo "$BASELINE_CRITERIA_MAX" > /tmp/lead_baseline_criteria_max
echo "$BASELINE_LAB_REQ_MAX" > /tmp/lead_baseline_lab_req_max
echo "$BASELINE_APPT_MAX" > /tmp/lead_baseline_appt_max
chmod 666 /tmp/lead_baseline_* 2>/dev/null || true

date +%Y-%m-%d > /tmp/lead_task_start_date
chmod 666 /tmp/lead_task_start_date 2>/dev/null || true

# Ensure window is maximized for visibility
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="