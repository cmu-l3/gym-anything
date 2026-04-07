#!/bin/bash
echo "=== Exporting admit_inpatient result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Load baselines
BASELINE_MAX=$(cat /tmp/baseline_inpatient_max.txt 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Baseline max: $BASELINE_MAX, Target patient: $TARGET_PATIENT_ID, Task start: $TASK_START_TIME"

# 3. Query for new inpatient registration for Ana Betz
# We use psql to output JSON directly for robust parsing of text fields (like admission_reason)
DB_QUERY="
WITH new_regs AS (
    SELECT 
        ir.id,
        ir.patient,
        ir.bed,
        ir.hospitalization_date::text as hosp_date,
        ir.state,
        ir.admission_reason,
        EXTRACT(EPOCH FROM ir.create_date)::int as create_ts
    FROM gnuhealth_inpatient_registration ir
    WHERE ir.id > $BASELINE_MAX
)
SELECT json_build_object(
    'any_new_records_count', (SELECT count(*) FROM new_regs),
    'target_record_found', EXISTS(SELECT 1 FROM new_regs WHERE patient = $TARGET_PATIENT_ID),
    'target_record', (
        SELECT row_to_json(t) FROM (
            SELECT id, bed, hosp_date, state, admission_reason, create_ts
            FROM new_regs 
            WHERE patient = $TARGET_PATIENT_ID 
            ORDER BY id DESC LIMIT 1
        ) t
    )
);
"

# Execute query and save JSON output to file
echo "Querying database..."
su - gnuhealth -c "psql -d health50 -At -c \"$DB_QUERY\"" > /tmp/db_result.json 2>/dev/null

# 4. Compile final result JSON wrapping the DB output
TEMP_JSON=$(mktemp)
python3 -c "
import json
import os

db_result_path = '/tmp/db_result.json'
db_data = {}
if os.path.exists(db_result_path):
    try:
        with open(db_result_path, 'r') as f:
            content = f.read().strip()
            if content:
                db_data = json.loads(content)
    except Exception as e:
        db_data = {'error': str(e)}

final_result = {
    'task_start_time': int('$TASK_START_TIME' or 0),
    'baseline_max': int('$BASELINE_MAX' or 0),
    'target_patient_id': int('$TARGET_PATIENT_ID' or 0),
    'db_result': db_data
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(final_result, f, indent=2)
"

# Move and set permissions
rm -f /tmp/admit_inpatient_result.json 2>/dev/null || sudo rm -f /tmp/admit_inpatient_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/admit_inpatient_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/admit_inpatient_result.json
chmod 666 /tmp/admit_inpatient_result.json 2>/dev/null || sudo chmod 666 /tmp/admit_inpatient_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/admit_inpatient_result.json:"
cat /tmp/admit_inpatient_result.json
echo "=== Export complete ==="