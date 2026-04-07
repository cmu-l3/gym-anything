#!/bin/bash
echo "=== Setting up record_family_history task ==="

source /workspace/scripts/task_utils.sh

# Wait for database to be ready
wait_for_postgres

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Ensure the required ICD-10 codes exist in the pathology table
for code in I25 E11 M32; do
    gnuhealth_db_query "
        INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
        SELECT COALESCE(MAX(id),0)+1, '$code', 'Test $code', true, 1, NOW(), 1, NOW() 
        FROM gnuhealth_pathology 
        WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_pathology WHERE code='$code');
    " 2>/dev/null || true
done

# Find the target patient: Ana Betz
ANA_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp 
    JOIN party_party pp ON gp.party = pp.id 
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%' LIMIT 1
" | tr -d '[:space:]')

if [ -z "$ANA_ID" ]; then
    echo "WARNING: Patient Ana Betz not found!"
    ANA_ID="0"
fi
echo "$ANA_ID" > /tmp/target_patient_id
chmod 666 /tmp/target_patient_id

# Dynamically resolve the family disease table name (varies slightly across Tryton versions)
TABLE_NAME=$(gnuhealth_db_query "
    SELECT table_name FROM information_schema.tables 
    WHERE table_name IN ('gnuhealth_family_disease', 'gnuhealth_patient_family_diseases', 'gnuhealth_patient_family_disease') 
    LIMIT 1
" | tr -d '[:space:]')

if [ -z "$TABLE_NAME" ]; then
    TABLE_NAME="gnuhealth_family_disease" # robust fallback
fi
echo "$TABLE_NAME" > /tmp/family_disease_table

# Clean out any pre-existing family diseases for Ana to ensure a clean starting state
gnuhealth_db_query "DELETE FROM $TABLE_NAME WHERE patient = $ANA_ID" 2>/dev/null || true

# Record baseline max ID to isolate records created during the task
BASELINE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM $TABLE_NAME" | tr -d '[:space:]')
echo "$BASELINE_MAX" > /tmp/baseline_max_id

# Warm up and focus the GNU Health application (Firefox client)
ensure_firefox_gnuhealth
sleep 2

# Take initial screenshot to document the starting state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="