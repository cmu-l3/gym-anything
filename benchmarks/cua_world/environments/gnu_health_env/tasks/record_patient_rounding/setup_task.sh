#!/bin/bash
echo "=== Setting up record_patient_rounding task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Ana Isabel Betz ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Patient Ana Isabel Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Isabel Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/rounding_target_patient_id
chmod 666 /tmp/rounding_target_patient_id 2>/dev/null || true

# --- 2. Ensure Ana has an active inpatient registration ---
ANA_INPATIENT_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_inpatient_registration 
    WHERE patient = $ANA_PATIENT_ID AND state IN ('hospitalized', 'admitted', 'draft', 'confirmed') 
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_INPATIENT_ID" ]; then
    echo "Creating active inpatient registration for Ana..."
    NEXT_REG_ID=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_inpatient_registration" | tr -d '[:space:]')
    gnuhealth_db_query "
        INSERT INTO gnuhealth_inpatient_registration 
        (id, patient, name, hospitalization_date, state, create_uid, create_date, write_uid, write_date)
        VALUES (
            $NEXT_REG_ID, $ANA_PATIENT_ID, 'INP-$NEXT_REG_ID', NOW(), 'hospitalized', 1, NOW(), 1, NOW()
        )
    " 2>/dev/null || true
    ANA_INPATIENT_ID=$NEXT_REG_ID
fi
echo "Ana's active inpatient registration ID: $ANA_INPATIENT_ID"

# --- 3. Inject contamination: Rounding record for Roberto Carlos ---
echo "Injecting contamination: Rounding record for Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    ROB_INPATIENT_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_inpatient_registration WHERE patient = $ROBERTO_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
    if [ -z "$ROB_INPATIENT_ID" ]; then
        NEXT_REG_ID=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_inpatient_registration" | tr -d '[:space:]')
        gnuhealth_db_query "INSERT INTO gnuhealth_inpatient_registration (id, patient, name, hospitalization_date, state, create_uid, create_date, write_uid, write_date) VALUES ($NEXT_REG_ID, $ROBERTO_PATIENT_ID, 'INP-$NEXT_REG_ID', NOW(), 'hospitalized', 1, NOW(), 1, NOW())" 2>/dev/null || true
        ROB_INPATIENT_ID=$NEXT_REG_ID
    fi
    
    NEXT_ROUNDING_ID=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_rounding" | tr -d '[:space:]')
    gnuhealth_db_query "
        INSERT INTO gnuhealth_patient_rounding 
        (id, name, temperature, systolic, diastolic, bpm, create_uid, create_date, write_uid, write_date)
        VALUES (
            $NEXT_ROUNDING_ID, $ROB_INPATIENT_ID, 37.5, 140, 88, 90, 1, NOW(), 1, NOW()
        )
    " 2>/dev/null || true
fi

# --- 4. Clean pre-existing rounding records for Ana to ensure a clean slate ---
echo "Cleaning pre-existing rounding records for Ana..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_rounding 
    WHERE name IN (SELECT id FROM gnuhealth_inpatient_registration WHERE patient = $ANA_PATIENT_ID)
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_ROUNDING_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_rounding" | tr -d '[:space:]')

echo "Baseline rounding max ID: $BASELINE_ROUNDING_MAX"
echo "$BASELINE_ROUNDING_MAX" > /tmp/rounding_baseline_max
chmod 666 /tmp/rounding_baseline_max 2>/dev/null || true

date +%Y-%m-%d > /tmp/rounding_task_start_date
chmod 666 /tmp/rounding_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running in Firefox ---
echo "Ensuring GNU Health web interface is open..."
ensure_gnuhealth_logged_in "http://localhost:8000/"

# Bring Firefox to front and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/rounding_initial_state.png

echo "=== Setup Complete ==="