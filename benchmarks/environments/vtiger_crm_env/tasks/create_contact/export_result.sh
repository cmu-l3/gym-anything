#!/bin/bash
echo "=== Exporting create_contact results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_contact_final.png

INITIAL_CONTACT_COUNT=$(cat /tmp/initial_contact_count.txt 2>/dev/null || echo "0")
CURRENT_CONTACT_COUNT=$(get_contact_count)

CONTACT_DATA=$(vtiger_db_query "SELECT c.contactid, c.firstname, c.lastname, c.email, c.phone, c.mobile, c.title, a.mailingstreet, a.mailingcity, a.mailingstate, a.mailingzip, a.mailingcountry FROM vtiger_contactdetails c LEFT JOIN vtiger_contactaddress a ON c.contactid=a.contactaddressid WHERE c.firstname='Nathan' AND c.lastname='Blackwood' LIMIT 1")

CONTACT_FOUND="false"
if [ -n "$CONTACT_DATA" ]; then
    CONTACT_FOUND="true"
    C_ID=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $1}')
    C_FIRST=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $2}')
    C_LAST=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $3}')
    C_EMAIL=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $4}')
    C_PHONE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $5}')
    C_MOBILE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $6}')
    C_TITLE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $7}')
    C_STREET=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $8}')
    C_CITY=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $9}')
    C_STATE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $10}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "contact_found": ${CONTACT_FOUND},
  "contact_id": "$(json_escape "${C_ID:-}")",
  "firstname": "$(json_escape "${C_FIRST:-}")",
  "lastname": "$(json_escape "${C_LAST:-}")",
  "email": "$(json_escape "${C_EMAIL:-}")",
  "phone": "$(json_escape "${C_PHONE:-}")",
  "mobile": "$(json_escape "${C_MOBILE:-}")",
  "title": "$(json_escape "${C_TITLE:-}")",
  "mailing_street": "$(json_escape "${C_STREET:-}")",
  "mailing_city": "$(json_escape "${C_CITY:-}")",
  "mailing_state": "$(json_escape "${C_STATE:-}")",
  "initial_count": ${INITIAL_CONTACT_COUNT},
  "current_count": ${CURRENT_CONTACT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_contact_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_contact_result.json"
echo "$RESULT_JSON"
echo "=== create_contact export complete ==="
