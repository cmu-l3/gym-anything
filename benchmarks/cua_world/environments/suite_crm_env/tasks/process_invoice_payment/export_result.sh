#!/bin/bash
set -e

echo "=== Exporting process_invoice_payment task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot "/tmp/task_final_state.png"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Invoice Data
INV_DATA=$(suitecrm_db_query "SELECT id, status, UNIX_TIMESTAMP(date_modified) FROM aos_invoices WHERE name='INV-90950: Meridian Quarterly Supplies' AND deleted=0 LIMIT 1")

INV_FOUND="false"
I_ID=""
I_STATUS=""
I_MTIME="0"

if [ -n "$INV_DATA" ]; then
    INV_FOUND="true"
    I_ID=$(echo "$INV_DATA" | awk -F'\t' '{print $1}')
    I_STATUS=$(echo "$INV_DATA" | awk -F'\t' '{print $2}')
    I_MTIME=$(echo "$INV_DATA" | awk -F'\t' '{print $3}')
fi

# 2. Query Note Data (filtering by name and ensuring it's not deleted)
NOTE_DATA=$(suitecrm_db_query "SELECT id, parent_type, parent_id, description FROM notes WHERE name='Wire Transfer Confirmed' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

NOTE_FOUND="false"
N_ID=""
N_PTYPE=""
N_PID=""
N_DESC=""

if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
    N_ID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $1}')
    N_PTYPE=$(echo "$NOTE_DATA" | awk -F'\t' '{print $2}')
    N_PID=$(echo "$NOTE_DATA" | awk -F'\t' '{print $3}')
    N_DESC=$(echo "$NOTE_DATA" | awk -F'\t' '{print $4}')
fi

# Construct Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": ${TASK_START:-0},
  "invoice_found": ${INV_FOUND},
  "invoice_id": "$(json_escape "${I_ID:-}")",
  "invoice_status": "$(json_escape "${I_STATUS:-}")",
  "invoice_mtime": ${I_MTIME:-0},
  "note_found": ${NOTE_FOUND},
  "note_id": "$(json_escape "${N_ID:-}")",
  "note_parent_type": "$(json_escape "${N_PTYPE:-}")",
  "note_parent_id": "$(json_escape "${N_PID:-}")",
  "note_desc": "$(json_escape "${N_DESC:-}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="