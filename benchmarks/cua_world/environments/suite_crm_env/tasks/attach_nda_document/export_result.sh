#!/bin/bash
echo "=== Exporting attach_nda_document results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/attach_nda_final.png

# Read variables
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count.txt 2>/dev/null || echo "0")
CURRENT_NOTE_COUNT=$(suitecrm_count "notes" "deleted=0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query the target Note
NOTE_DATA=$(suitecrm_db_query "SELECT id, name, parent_type, parent_id, filename, description FROM notes WHERE name='Executed MNDA - TechFlow Solutions' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

NOTE_FOUND="false"
N_ID=""
N_NAME=""
N_PTYPE=""
N_PID=""
N_FNAME=""
N_DESC=""
ACCOUNT_NAME=""
FILE_UPLOADED="false"
UPLOAD_SIZE="0"

if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
    N_ID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $1}')
    N_NAME=$(echo "$NOTE_DATA" | awk -F'\t' '{print $2}')
    N_PTYPE=$(echo "$NOTE_DATA" | awk -F'\t' '{print $3}')
    N_PID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $4}')
    N_FNAME=$(echo "$NOTE_DATA" | awk -F'\t' '{print $5}')
    N_DESC=$(echo "$NOTE_DATA" | awk -F'\t' '{print $6}')

    # Resolve parent account name
    if [ "$N_PTYPE" = "Accounts" ] && [ -n "$N_PID" ]; then
        ACCOUNT_NAME=$(suitecrm_db_query "SELECT name FROM accounts WHERE id='$N_PID' AND deleted=0 LIMIT 1")
    fi

    # Check physical file blob inside the container
    if docker exec suitecrm-app test -f "/var/www/html/upload/$N_ID"; then
        FILE_UPLOADED="true"
        UPLOAD_SIZE=$(docker exec suitecrm-app stat -c %s "/var/www/html/upload/$N_ID" 2>/dev/null || echo "0")
    fi
fi

# Build JSON Result
RESULT_JSON=$(cat << JSONEOF
{
  "note_found": ${NOTE_FOUND},
  "note_id": "$(json_escape "${N_ID:-}")",
  "name": "$(json_escape "${N_NAME:-}")",
  "parent_type": "$(json_escape "${N_PTYPE:-}")",
  "parent_id": "$(json_escape "${N_PID:-}")",
  "parent_account_name": "$(json_escape "${ACCOUNT_NAME:-}")",
  "filename": "$(json_escape "${N_FNAME:-}")",
  "description": "$(json_escape "${N_DESC:-}")",
  "file_uploaded_in_container": ${FILE_UPLOADED},
  "upload_size_bytes": ${UPLOAD_SIZE},
  "initial_count": ${INITIAL_NOTE_COUNT},
  "current_count": ${CURRENT_NOTE_COUNT},
  "task_start_time": ${TASK_START}
}
JSONEOF
)

safe_write_result "/tmp/attach_nda_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/attach_nda_result.json"
echo "$RESULT_JSON"
echo "=== attach_nda_document export complete ==="