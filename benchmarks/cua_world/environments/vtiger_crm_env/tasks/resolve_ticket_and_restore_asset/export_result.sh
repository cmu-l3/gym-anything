#!/bin/bash
echo "=== Exporting resolve_ticket_and_restore_asset results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
source /tmp/task_entity_ids.txt

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Query the exact records we created during setup
TICKET_STATUS=$(vtiger_db_query "SELECT status FROM vtiger_troubletickets WHERE ticketid=$TICKET_ID" | sed 's/\t/ /g' | tr -d '\r\n')
TICKET_SOLUTION=$(vtiger_db_query "SELECT solution FROM vtiger_troubletickets WHERE ticketid=$TICKET_ID" | sed 's/\t/ /g' | tr -d '\r\n')
TICKET_MTIME=$(vtiger_db_query "SELECT UNIX_TIMESTAMP(modifiedtime) FROM vtiger_crmentity WHERE crmid=$TICKET_ID" | tr -d '[:space:]')

ASSET_STATUS=$(vtiger_db_query "SELECT assetstatus FROM vtiger_assets WHERE assetsid=$ASSET_ID" | sed 's/\t/ /g' | tr -d '\r\n')
ASSET_DATE=$(vtiger_db_query "SELECT dateinservice FROM vtiger_assets WHERE assetsid=$ASSET_ID" | sed 's/\t/ /g' | tr -d '\r\n')
ASSET_MTIME=$(vtiger_db_query "SELECT UNIX_TIMESTAMP(modifiedtime) FROM vtiger_crmentity WHERE crmid=$ASSET_ID" | tr -d '[:space:]')

# Query comments linked to the ticket
COMMENTS=$(vtiger_db_query "SELECT GROUP_CONCAT(commentcontent SEPARATOR ' || ') FROM vtiger_modcomments WHERE related_to=$TICKET_ID" | sed 's/\t/ /g' | tr -d '\r\n')

# Check if application is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Build the JSON object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "app_was_running": $APP_RUNNING,
  "ticket": {
    "id": "$TICKET_ID",
    "status": "$(json_escape "${TICKET_STATUS:-}")",
    "solution": "$(json_escape "${TICKET_SOLUTION:-}")",
    "comments": "$(json_escape "${COMMENTS:-}")",
    "modified_timestamp": "${TICKET_MTIME:-0}"
  },
  "asset": {
    "id": "$ASSET_ID",
    "status": "$(json_escape "${ASSET_STATUS:-}")",
    "date_in_service": "$(json_escape "${ASSET_DATE:-}")",
    "modified_timestamp": "${ASSET_MTIME:-0}"
  }
}
EOF

# Move to final destination safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="