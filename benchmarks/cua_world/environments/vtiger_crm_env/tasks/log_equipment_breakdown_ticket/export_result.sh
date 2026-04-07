#!/bin/bash
echo "=== Exporting log_equipment_breakdown_ticket results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Asset details and modification time
ASSET_QUERY="SELECT a.assetstatus, a.assetsid, c.modifiedtime FROM vtiger_assets a JOIN vtiger_crmentity c ON a.assetsid=c.crmid WHERE a.serialnumber='SN-US-2024-9981' LIMIT 1"
ASSET_DATA=$(vtiger_db_query "$ASSET_QUERY")
ASSET_STATUS=$(echo "$ASSET_DATA" | awk -F'\t' '{print $1}')
ASSET_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $2}')
ASSET_MTIME=$(echo "$ASSET_DATA" | awk -F'\t' '{print $3}')
ASSET_MTIME_SEC=$(date -d "$ASSET_MTIME" +%s 2>/dev/null || echo "0")

# Get Ticket details and creation time
TICKET_QUERY="SELECT t.ticketid, t.title, t.priority, t.status, t.parent_id, c.createdtime FROM vtiger_troubletickets t JOIN vtiger_crmentity c ON t.ticketid=c.crmid WHERE t.title='Dead Transducer Probe' ORDER BY t.ticketid DESC LIMIT 1"
TICKET_DATA=$(vtiger_db_query "$TICKET_QUERY")

TICKET_FOUND="false"
T_ID=""
T_TITLE=""
T_PRIORITY=""
T_STATUS=""
T_PARENT_ID=""
TICKET_CTIME_SEC="0"

if [ -n "$TICKET_DATA" ]; then
    TICKET_FOUND="true"
    T_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
    T_TITLE=$(echo "$TICKET_DATA" | awk -F'\t' '{print $2}')
    T_PRIORITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')
    T_STATUS=$(echo "$TICKET_DATA" | awk -F'\t' '{print $4}')
    T_PARENT_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $5}')
    TICKET_CTIME=$(echo "$TICKET_DATA" | awk -F'\t' '{print $6}')
    TICKET_CTIME_SEC=$(date -d "$TICKET_CTIME" +%s 2>/dev/null || echo "0")
fi

# Get Organization ID
ORG_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='Memorial Healthcare System' LIMIT 1" | tr -d '[:space:]')

# Check Ticket-Asset Linkage
LINK_EXISTS="false"
if [ -n "$T_ID" ] && [ -n "$ASSET_ID" ]; then
    LINK_QUERY="SELECT COUNT(*) FROM vtiger_crmentityrel WHERE (crmid='$T_ID' AND relcrmid='$ASSET_ID') OR (crmid='$ASSET_ID' AND relcrmid='$T_ID')"
    LINK_COUNT=$(vtiger_db_query "$LINK_QUERY" | tr -d '[:space:]')
    if [ "$LINK_COUNT" -gt 0 ]; then
        LINK_EXISTS="true"
    fi
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

RESULT_JSON=$(cat << JSONEOF
{
  "asset_status": "$(json_escape "${ASSET_STATUS:-}")",
  "asset_mtime_sec": ${ASSET_MTIME_SEC},
  "ticket_found": ${TICKET_FOUND},
  "ticket_id": "$(json_escape "${T_ID:-}")",
  "ticket_title": "$(json_escape "${T_TITLE:-}")",
  "ticket_priority": "$(json_escape "${T_PRIORITY:-}")",
  "ticket_status": "$(json_escape "${T_STATUS:-}")",
  "ticket_parent_id": "$(json_escape "${T_PARENT_ID:-}")",
  "ticket_ctime_sec": ${TICKET_CTIME_SEC},
  "org_id": "$(json_escape "${ORG_ID:-}")",
  "link_exists": ${LINK_EXISTS},
  "task_start": ${TASK_START},
  "task_end": ${TASK_END}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== log_equipment_breakdown_ticket export complete ==="