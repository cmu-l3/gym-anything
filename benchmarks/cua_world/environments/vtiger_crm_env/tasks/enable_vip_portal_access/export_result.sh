#!/bin/bash
echo "=== Exporting enable_vip_portal_access results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Extract timing metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_TICKET_COUNT=$(cat /tmp/initial_ticket_count.txt 2>/dev/null || echo "0")
CURRENT_TICKET_COUNT=$(get_ticket_count)

# 3. Extract Contact State
# Queries contact details, portal details, and modification timestamp
CONTACT_DATA=$(vtiger_db_query "SELECT c.contactid, c.title, c.department, d.portal, d.support_start_date, d.support_end_date, UNIX_TIMESTAMP(e.modifiedtime) FROM vtiger_contactdetails c LEFT JOIN vtiger_customerdetails d ON c.contactid = d.customerid JOIN vtiger_crmentity e ON c.contactid = e.crmid WHERE c.firstname='Elena' AND c.lastname='Rostova' LIMIT 1")

C_FOUND="false"
if [ -n "$CONTACT_DATA" ]; then
    C_FOUND="true"
    C_ID=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $1}')
    C_TITLE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $2}')
    C_DEPT=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $3}')
    C_PORTAL=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $4}')
    C_START=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $5}')
    C_END=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $6}')
    C_MODIFIED=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $7}')
fi

# 4. Extract Ticket State
# Queries the latest ticket matching the requested title
TICKET_DATA=$(vtiger_db_query "SELECT t.ticketid, t.title, t.status, t.priority, t.contact_id, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_troubletickets t JOIN vtiger_crmentity e ON t.ticketid = e.crmid WHERE t.title='VIP Onboarding - Elena Rostova' ORDER BY t.ticketid DESC LIMIT 1")

T_FOUND="false"
if [ -n "$TICKET_DATA" ]; then
    T_FOUND="true"
    T_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
    T_TITLE=$(echo "$TICKET_DATA" | awk -F'\t' '{print $2}')
    T_STATUS=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')
    T_PRIORITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $4}')
    T_CONTACT_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $5}')
    T_CREATED=$(echo "$TICKET_DATA" | awk -F'\t' '{print $6}')
fi

# 5. Build and Save JSON Result
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "task_end_time": ${TASK_END},
  "initial_ticket_count": ${INITIAL_TICKET_COUNT},
  "current_ticket_count": ${CURRENT_TICKET_COUNT},
  
  "contact_found": ${C_FOUND},
  "contact_id": "$(json_escape "${C_ID:-}")",
  "contact_title": "$(json_escape "${C_TITLE:-}")",
  "contact_department": "$(json_escape "${C_DEPT:-}")",
  "contact_portal": "$(json_escape "${C_PORTAL:-}")",
  "contact_support_start": "$(json_escape "${C_START:-}")",
  "contact_support_end": "$(json_escape "${C_END:-}")",
  "contact_modified_time": "$(json_escape "${C_MODIFIED:-0}")",
  
  "ticket_found": ${T_FOUND},
  "ticket_id": "$(json_escape "${T_ID:-}")",
  "ticket_title": "$(json_escape "${T_TITLE:-}")",
  "ticket_status": "$(json_escape "${T_STATUS:-}")",
  "ticket_priority": "$(json_escape "${T_PRIORITY:-}")",
  "ticket_contact_id": "$(json_escape "${T_CONTACT_ID:-}")",
  "ticket_created_time": "$(json_escape "${T_CREATED:-0}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result JSON written to /tmp/task_result.json:"
cat "/tmp/task_result.json"
echo "=== enable_vip_portal_access export complete ==="