#!/bin/bash
echo "=== Setting up record_newborn_delivery task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/newborn_task_start_date

# --- 1. Find Mother Ana Isabel Betz ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Mother Ana Isabel Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Isabel Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/newborn_target_mother_id

# --- 2. Clean slate: Remove any existing Sofia Betz patients ---
echo "Cleaning any pre-existing 'Sofia Betz' patients..."
SOFIA_PARTY_IDS=$(gnuhealth_db_query "
    SELECT id FROM party_party 
    WHERE name ILIKE '%Sofia%' AND lastname ILIKE '%Betz%'
")
for PID in $SOFIA_PARTY_IDS; do
    if [ -n "$PID" ]; then
        gnuhealth_db_query "DELETE FROM gnuhealth_appointment WHERE patient IN (SELECT id FROM gnuhealth_patient WHERE party = $PID)" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM gnuhealth_patient WHERE party = $PID" 2>/dev/null || true
        gnuhealth_db_query "DELETE FROM party_party WHERE id = $PID" 2>/dev/null || true
    fi
done

# --- 3. Clean slate: Remove any existing newborns for Ana ---
echo "Cleaning pre-existing newborn records for Ana..."
gnuhealth_db_query "DELETE FROM gnuhealth_newborn WHERE mother = $ANA_PATIENT_ID" 2>/dev/null || true

# --- 4. Contamination: Create a distractor newborn on a different patient (Luna) ---
echo "Injecting contamination: Distractor newborn on patient Luna..."
LUNA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Luna%' LIMIT 1" | tr -d '[:space:]')

if [ -n "$LUNA_PATIENT_ID" ]; then
    EXISTING_CONTAM=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_newborn WHERE mother = $LUNA_PATIENT_ID" | tr -d '[:space:]')
    
    if [ "${EXISTING_CONTAM:-0}" -eq 0 ]; then
        gnuhealth_db_query "
            INSERT INTO gnuhealth_newborn (
                id, mother, newborn_name, birth_date, sex, weight, length, cephalic_perimeter, apgar1, apgar5, create_uid, create_date, write_uid, write_date
            ) VALUES (
                (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_newborn),
                $LUNA_PATIENT_ID, 'DistractorBaby', NOW(), 'm', 2800, 48, 33, 7, 8, 1, NOW(), 1, NOW()
            )
        " 2>/dev/null || true
    fi
fi

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_NEWBORN_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_newborn" | tr -d '[:space:]')
BASELINE_PATIENT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient" | tr -d '[:space:]')
BASELINE_PARTY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM party_party" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline newborn max: $BASELINE_NEWBORN_MAX"
echo "Baseline patient max: $BASELINE_PATIENT_MAX"
echo "Baseline party max: $BASELINE_PARTY_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_NEWBORN_MAX" > /tmp/newborn_baseline_newborn_max
echo "$BASELINE_PATIENT_MAX" > /tmp/newborn_baseline_patient_max
echo "$BASELINE_PARTY_MAX" > /tmp/newborn_baseline_party_max
echo "$BASELINE_APPT_MAX" > /tmp/newborn_baseline_appt_max
chmod 666 /tmp/newborn_baseline_* 2>/dev/null || true

# --- 6. Start browser and login ---
echo "Starting Firefox and ensuring login..."
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

# Take initial screenshot
take_screenshot /tmp/newborn_initial_state.png

echo "=== Setup Complete ==="