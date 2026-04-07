#!/bin/bash
set -e
echo "=== Exporting create_service_contract results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SC_COUNT=$(cat /tmp/initial_sc_count.txt 2>/dev/null || echo "0")
EXPECTED_ORG_ID=$(cat /tmp/riverside_org_id.txt 2>/dev/null || echo "")
EXPECTED_CONTACT_ID=$(cat /tmp/diana_contact_id.txt 2>/dev/null || echo "")

# Get current count
FINAL_SC_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_servicecontracts sc JOIN vtiger_crmentity ce ON sc.servicecontractsid = ce.crmid WHERE ce.deleted = 0" | tr -d '[:space:]')

# Find the service contract by subject
SC_DATA=$(vtiger_db_query "
    SELECT sc.servicecontractsid, sc.subject, sc.start_date, sc.end_date,
           sc.tracking_unit, sc.total_units, sc.used_units,
           sc.contract_type, sc.contract_priority, sc.contract_status,
           sc.sc_related_to, sc.contact_id, UNIX_TIMESTAMP(ce.createdtime) as created_ts
    FROM vtiger_servicecontracts sc
    JOIN vtiger_crmentity ce ON sc.servicecontractsid = ce.crmid
    WHERE ce.deleted = 0
      AND sc.subject LIKE '%Annual Grounds Maintenance%Riverside%'
    ORDER BY ce.createdtime DESC
    LIMIT 1
")

SC_FOUND="false"
if [ -n "$SC_DATA" ]; then
    SC_FOUND="true"
    SC_ID=$(echo "$SC_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    SC_SUBJECT=$(echo "$SC_DATA" | awk -F'\t' '{print $2}' | xargs)
    SC_START=$(echo "$SC_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    SC_END=$(echo "$SC_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    SC_TRACKING=$(echo "$SC_DATA" | awk -F'\t' '{print $5}' | xargs)
    SC_TOTAL=$(echo "$SC_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
    SC_USED=$(echo "$SC_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
    SC_TYPE=$(echo "$SC_DATA" | awk -F'\t' '{print $8}' | xargs)
    SC_PRIORITY=$(echo "$SC_DATA" | awk -F'\t' '{print $9}' | xargs)
    SC_STATUS=$(echo "$SC_DATA" | awk -F'\t' '{print $10}' | xargs)
    SC_ORG_ID=$(echo "$SC_DATA" | awk -F'\t' '{print $11}' | tr -d '[:space:]')
    SC_CON_ID=$(echo "$SC_DATA" | awk -F'\t' '{print $12}' | tr -d '[:space:]')
    SC_CREATED_TS=$(echo "$SC_DATA" | awk -F'\t' '{print $13}' | tr -d '[:space:]')
    
    # Check if linked to correct Org Name (fallback if ID mismatch)
    LINKED_ORG_NAME=$(vtiger_db_query "SELECT accountname FROM vtiger_account WHERE accountid = '$SC_ORG_ID'" | xargs)
    
    # Check if linked to correct Contact Name (fallback if ID mismatch)
    LINKED_CON_NAME=$(vtiger_db_query "SELECT CONCAT(firstname, ' ', lastname) FROM vtiger_contactdetails WHERE contactid = '$SC_CON_ID'" | xargs)
else
    SC_ID=""
    SC_SUBJECT=""
    SC_START=""
    SC_END=""
    SC_TRACKING=""
    SC_TOTAL=""
    SC_USED=""
    SC_TYPE=""
    SC_PRIORITY=""
    SC_STATUS=""
    SC_ORG_ID=""
    SC_CON_ID=""
    SC_CREATED_TS="0"
    LINKED_ORG_NAME=""
    LINKED_CON_NAME=""
fi

# Write result to JSON
TEMP_JSON=$(mktemp /tmp/sc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": ${TASK_START_TIME},
  "initial_count": ${INITIAL_SC_COUNT},
  "final_count": ${FINAL_SC_COUNT},
  "expected_org_id": "$(json_escape "${EXPECTED_ORG_ID}")",
  "expected_contact_id": "$(json_escape "${EXPECTED_CONTACT_ID}")",
  "sc_found": ${SC_FOUND},
  "sc_id": "$(json_escape "${SC_ID}")",
  "subject": "$(json_escape "${SC_SUBJECT}")",
  "start_date": "$(json_escape "${SC_START}")",
  "end_date": "$(json_escape "${SC_END}")",
  "tracking_unit": "$(json_escape "${SC_TRACKING}")",
  "total_units": "$(json_escape "${SC_TOTAL}")",
  "used_units": "$(json_escape "${SC_USED}")",
  "contract_type": "$(json_escape "${SC_TYPE}")",
  "contract_priority": "$(json_escape "${SC_PRIORITY}")",
  "contract_status": "$(json_escape "${SC_STATUS}")",
  "sc_org_id": "$(json_escape "${SC_ORG_ID}")",
  "sc_con_id": "$(json_escape "${SC_CON_ID}")",
  "linked_org_name": "$(json_escape "${LINKED_ORG_NAME}")",
  "linked_contact_name": "$(json_escape "${LINKED_CON_NAME}")",
  "created_ts": ${SC_CREATED_TS}
}
EOF

safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="