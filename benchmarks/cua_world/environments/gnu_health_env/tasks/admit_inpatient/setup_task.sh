#!/bin/bash
echo "=== Setting up admit_inpatient task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres 60

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# --- 1. Find target patient (Ana Isabel Betz) ---
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
echo "Target Patient ID (Ana Betz): $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/target_patient_id.txt
chmod 666 /tmp/target_patient_id.txt 2>/dev/null || true

# --- 2. Clean up any prior inpatient registrations for Ana Betz ---
# This ensures a clean state in case of task restarts
gnuhealth_db_query "DELETE FROM gnuhealth_inpatient_registration WHERE patient = $ANA_PATIENT_ID" 2>/dev/null || true
echo "Cleared prior inpatient registrations for Ana Betz."

# --- 3. Ensure hospital infrastructure exists (ward + beds) ---
WARD_COUNT=$(gnuhealth_count "gnuhealth_hospital_ward")
echo "Existing wards: ${WARD_COUNT:-0}"

if [ "${WARD_COUNT:-0}" -eq 0 ]; then
    echo "No wards found. Creating General Medicine Ward with beds..."
    INSTITUTION_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_institution LIMIT 1")
    if [ -z "$INSTITUTION_ID" ]; then
        INSTITUTION_ID="NULL"
    fi

    # Create a ward
    gnuhealth_db_query "
        INSERT INTO gnuhealth_hospital_ward (name, institution, state, gender, extra_info, create_uid, create_date, write_uid, write_date)
        VALUES ('General Medicine Ward', $INSTITUTION_ID, 'active', 'unisex', 'General observation ward', 1, NOW(), 1, NOW())
    " 2>/dev/null || true

    WARD_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_hospital_ward WHERE name = 'General Medicine Ward' LIMIT 1" | tr -d '[:space:]')

    if [ -n "$WARD_ID" ]; then
        # Create 4 beds in the ward
        for BED_NUM in 1 2 3 4; do
            gnuhealth_db_query "
                INSERT INTO gnuhealth_hospital_bed (name, ward, state, bed_type, create_uid, create_date, write_uid, write_date)
                VALUES ('GM-${BED_NUM}', $WARD_ID, 'free', 'gatch', 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        done
        echo "Created 4 beds in General Medicine Ward."
    fi
fi

# Ensure at least one bed is free
FREE_BED_COUNT=$(gnuhealth_count "gnuhealth_hospital_bed" "state = 'free'")
if [ "${FREE_BED_COUNT:-0}" -eq 0 ]; then
    echo "No free beds found. Forcing the first bed to 'free' state..."
    FIRST_BED_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_hospital_bed LIMIT 1" | tr -d '[:space:]')
    if [ -n "$FIRST_BED_ID" ]; then
        gnuhealth_db_query "UPDATE gnuhealth_hospital_bed SET state = 'free' WHERE id = $FIRST_BED_ID" 2>/dev/null || true
    fi
fi
echo "Available free beds: $(gnuhealth_count "gnuhealth_hospital_bed" "state = 'free'")"

# --- 4. Record baseline count ---
BASELINE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_inpatient_registration" | tr -d '[:space:]')
echo "Baseline Inpatient Registration MAX(id): $BASELINE_MAX"
echo "$BASELINE_MAX" > /tmp/baseline_inpatient_max.txt
chmod 666 /tmp/baseline_inpatient_max.txt 2>/dev/null || true

# --- 5. Start browser and log in ---
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="