#!/bin/bash
echo "=== Setting up Record Patient Allergy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp check)
date +%s > /tmp/task_start_time.txt

# Wait for PostgreSQL to be ready
wait_for_postgres 60

# Ensure GNU Health server is running
systemctl start gnuhealth 2>/dev/null || true
sleep 5

# Ensure Z88.0 pathology exists in the database
gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, name, code, category, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology),
        'Allergy status to penicillin',
        'Z88.0',
        (SELECT id FROM gnuhealth_pathology_category LIMIT 1),
        true,
        1,
        NOW(),
        1,
        NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_pathology WHERE code = 'Z88.0'
    );
" 2>/dev/null || true

# Get Ana Betz's patient ID
TARGET_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND (pp.lastname ILIKE '%Betz%' OR pp.name ILIKE '%Betz%')
    LIMIT 1
" | tr -d '[:space:]')

if [ -z "$TARGET_PATIENT_ID" ]; then
    echo "WARNING: Could not find Ana Betz in the database!"
    TARGET_PATIENT_ID=0
fi

echo "$TARGET_PATIENT_ID" > /tmp/target_patient_id.txt

# Record initial allergy count for anti-gaming baseline
INITIAL_ALLERGY_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE name = $TARGET_PATIENT_ID AND is_allergy = true
" | tr -d '[:space:]')

echo "${INITIAL_ALLERGY_COUNT:-0}" > /tmp/initial_allergy_count.txt

# Ensure Firefox is open and logged into GNU Health
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# Focus and maximize Firefox
focus_firefox
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="