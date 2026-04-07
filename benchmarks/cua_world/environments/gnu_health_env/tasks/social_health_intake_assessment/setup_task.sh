#!/bin/bash
echo "=== Setting up social_health_intake_assessment task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Matt Zenon Betz ---
MATT_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Matt%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$MATT_PATIENT_ID" ]; then
    # Try by full name concat
    MATT_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(pp.name, ' ', COALESCE(pp.lastname,'')) ILIKE '%Matt%Betz%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$MATT_PATIENT_ID" ]; then
    echo "FATAL: Patient Matt Zenon Betz not found in demo database. Aborting."
    exit 1
fi
echo "Matt Zenon Betz patient_id: $MATT_PATIENT_ID"
echo "$MATT_PATIENT_ID" > /tmp/sdoh_target_patient_id
chmod 666 /tmp/sdoh_target_patient_id 2>/dev/null || true

# --- 2. Get party_party id for Matt ---
MATT_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party
    FROM gnuhealth_patient gp
    WHERE gp.id = $MATT_PATIENT_ID
    LIMIT 1" | tr -d '[:space:]')
echo "Matt Zenon Betz party_id: $MATT_PARTY_ID"
echo "$MATT_PARTY_ID" > /tmp/sdoh_target_party_id
chmod 666 /tmp/sdoh_target_party_id 2>/dev/null || true

# --- 3. Reset Matt's socioeconomic fields to NULL (clean start) ---
echo "Clearing Matt's socioeconomic fields for clean task start..."
if [ -n "$MATT_PARTY_ID" ]; then
    gnuhealth_db_query "
        UPDATE party_party
        SET education = NULL, occupation = NULL
        WHERE id = $MATT_PARTY_ID
    " 2>/dev/null || true
fi

# --- 4. Remove existing lifestyle records for Matt ---
echo "Clearing existing lifestyle records for Matt..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient_lifestyle = $MATT_PATIENT_ID
" 2>/dev/null || true
# Alternative column name
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient = $MATT_PATIENT_ID
" 2>/dev/null || true

# --- 5. Remove existing family disease records for Matt ---
echo "Clearing existing family history for Matt..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_family_diseases
    WHERE patient = $MATT_PATIENT_ID
" 2>/dev/null || true

# --- 6. Remove existing phone contacts for Matt (but keep non-phone contacts) ---
echo "Clearing existing phone contacts for Matt..."
if [ -n "$MATT_PARTY_ID" ]; then
    gnuhealth_db_query "
        DELETE FROM party_contact_mechanism
        WHERE party = $MATT_PARTY_ID AND type = 'phone'
    " 2>/dev/null || true
    # Also try 'mobile' type
    gnuhealth_db_query "
        DELETE FROM party_contact_mechanism
        WHERE party = $MATT_PARTY_ID AND type IN ('mobile', 'phone', 'other')
    " 2>/dev/null || true
fi

# --- 7. Record baselines ---
echo "Recording baseline state..."
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')
BASELINE_FAMILY_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_family_diseases" | tr -d '[:space:]')
BASELINE_CONTACT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM party_contact_mechanism" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline lifestyle max: $BASELINE_LIFESTYLE_MAX"
echo "Baseline family disease max: $BASELINE_FAMILY_DISEASE_MAX"
echo "Baseline contact max: $BASELINE_CONTACT_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_LIFESTYLE_MAX" > /tmp/sdoh_baseline_lifestyle_max
echo "$BASELINE_FAMILY_DISEASE_MAX" > /tmp/sdoh_baseline_family_disease_max
echo "$BASELINE_CONTACT_MAX" > /tmp/sdoh_baseline_contact_max
echo "$BASELINE_APPT_MAX" > /tmp/sdoh_baseline_appt_max
for f in /tmp/sdoh_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/sdoh_task_start_date
chmod 666 /tmp/sdoh_task_start_date 2>/dev/null || true

# --- 8. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/sdoh_initial_state.png

echo "=== social_health_intake_assessment setup complete ==="
echo "Target patient: Matt Zenon Betz (patient_id=$MATT_PATIENT_ID, party_id=$MATT_PARTY_ID)"
echo "Tasks to complete:"
echo "  1. Update Socioeconomics tab: Education=University, Occupation=Engineer"
echo "  2. Create Lifestyle record: Physical activity=Active, Tobacco=Non-smoker"
echo "  3. Add Family History: Cardiovascular/Coronary Artery Disease (ICD-10 I25.x)"
echo "  4. Add mobile phone contact to party record"
echo "  5. Schedule preventive care appointment in 150-200 days (Dr. Cordara)"
