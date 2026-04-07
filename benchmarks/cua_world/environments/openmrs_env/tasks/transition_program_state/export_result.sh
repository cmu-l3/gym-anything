#!/bin/bash
# Export: transition_program_state task
# Queries database for program states and exports to JSON

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Patient Program States
# We look for Olen Bayer's program states
# We fetch: Program Name, Workflow Name, State Name, Start Date, End Date, Date Created, Date Completed (enrollment)
SQL_QUERY="
SELECT 
    p.name AS program_name,
    cn_workflow.name AS workflow_name,
    cn_state.name AS state_name,
    ps.start_date,
    ps.end_date,
    ps.date_created AS state_date_created,
    pp.date_completed AS enrollment_date_completed,
    pp.date_enrolled
FROM patient_state ps
JOIN patient_program pp ON ps.patient_program_id = pp.patient_program_id
JOIN person_name pn ON pp.patient_id = pn.person_id
JOIN program_workflow_state pws ON ps.state = pws.program_workflow_state_id
JOIN program_workflow pw ON pws.program_workflow_id = pw.program_workflow_id
JOIN program p ON pw.program_id = p.program_id
LEFT JOIN concept_name cn_workflow ON pw.concept_id = cn_workflow.concept_id 
    AND cn_workflow.locale = 'en' AND cn_workflow.concept_name_type = 'FULLY_SPECIFIED'
LEFT JOIN concept_name cn_state ON pws.concept_id = cn_state.concept_id 
    AND cn_state.locale = 'en' AND cn_state.concept_name_type = 'FULLY_SPECIFIED'
WHERE pn.given_name = 'Olen' AND pn.family_name = 'Bayer'
  AND p.name LIKE '%HIV%'
  AND ps.voided = 0
ORDER BY ps.start_date ASC;
"

# Run query via helper
RAW_DATA=$(omrs_db_query "$SQL_QUERY")

# Convert tab-separated output to JSON array
# Format: program_name, workflow_name, state_name, start_date, end_date, state_date_created, enrollment_date_completed, date_enrolled
JSON_STATES=$(echo "$RAW_DATA" | python3 -c "
import sys, json, csv
reader = csv.reader(sys.stdin, delimiter='\t')
states = []
for row in reader:
    if len(row) >= 8:
        states.append({
            'program': row[0],
            'workflow': row[1],
            'state': row[2],
            'start_date': row[3],
            'end_date': row[4] if row[4] != 'NULL' else None,
            'state_date_created': row[5],
            'enrollment_completed': row[6] if row[6] != 'NULL' else None,
            'date_enrolled': row[7]
        })
print(json.dumps(states))
")

# Check if app was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "patient_states": $JSON_STATES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="