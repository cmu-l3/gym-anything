#!/bin/bash
echo "=== Exporting attach_diagnostic_log_to_case results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# 1. Fetch Contact ID (used to verify Note relational mapping)
CONTACT_ID=$(suitecrm_db_query "SELECT id FROM contacts WHERE first_name='Alice' AND last_name='Smith' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

# 2. Fetch Target Case Data
CASE_DATA=$(suitecrm_db_query "SELECT id, status, priority FROM cases WHERE name='Web Server Random Crashes - TechCorp' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")
C_ID=""
C_STATUS=""
C_PRIORITY=""
if [ -n "$CASE_DATA" ]; then
    C_ID=$(echo "$CASE_DATA" | awk -F'\t' '{print $1}')
    C_STATUS=$(echo "$CASE_DATA" | awk -F'\t' '{print $2}')
    C_PRIORITY=$(echo "$CASE_DATA" | awk -F'\t' '{print $3}')
fi

# 3. Fetch Note Data linked to the uploaded file
NOTE_DATA=$(suitecrm_db_query "SELECT id, parent_type, parent_id, contact_id, filename, date_entered FROM notes WHERE name='Client Apache Error Log' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")
N_ID=""
N_PTYPE=""
N_PID=""
N_CID=""
N_FILE=""
N_DATE=""
if [ -n "$NOTE_DATA" ]; then
    N_ID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $1}')
    N_PTYPE=$(echo "$NOTE_DATA" | awk -F'\t' '{print $2}')
    N_PID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $3}')
    N_CID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $4}')
    N_FILE=$(echo "$NOTE_DATA" | awk -F'\t' '{print $5}')
    N_DATE=$(echo "$NOTE_DATA" | awk -F'\t' '{print $6}')
fi

APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "contact_id": "$(json_escape "${CONTACT_ID:-}")",
    "case_id": "$(json_escape "${C_ID:-}")",
    "case_status": "$(json_escape "${C_STATUS:-}")",
    "case_priority": "$(json_escape "${C_PRIORITY:-}")",
    "note_id": "$(json_escape "${N_ID:-}")",
    "note_parent_type": "$(json_escape "${N_PTYPE:-}")",
    "note_parent_id": "$(json_escape "${N_PID:-}")",
    "note_contact_id": "$(json_escape "${N_CID:-}")",
    "note_filename": "$(json_escape "${N_FILE:-}")",
    "note_date_entered": "$(json_escape "${N_DATE:-}")"
}
EOF

safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="