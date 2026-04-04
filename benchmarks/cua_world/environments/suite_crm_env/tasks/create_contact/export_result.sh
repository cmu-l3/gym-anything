#!/bin/bash
echo "=== Exporting create_contact results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_contact_final.png

INITIAL_CONTACT_COUNT=$(cat /tmp/initial_contact_count.txt 2>/dev/null || echo "0")
CURRENT_CONTACT_COUNT=$(get_contact_count)

CONTACT_DATA=$(suitecrm_db_query "SELECT c.id, c.first_name, c.last_name, c.title, c.department, c.phone_work, c.phone_mobile, ea.email_address, c.primary_address_street, c.primary_address_city, c.primary_address_state, c.primary_address_postalcode FROM contacts c LEFT JOIN email_addr_bean_rel eabr ON c.id=eabr.bean_id AND eabr.bean_module='Contacts' AND eabr.deleted=0 LEFT JOIN email_addresses ea ON eabr.email_address_id=ea.id AND ea.deleted=0 WHERE c.first_name='Marcus' AND c.last_name='Whitfield' AND c.deleted=0 LIMIT 1")

CONTACT_FOUND="false"
if [ -n "$CONTACT_DATA" ]; then
    CONTACT_FOUND="true"
    C_ID=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $1}')
    C_FIRST=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $2}')
    C_LAST=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $3}')
    C_TITLE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $4}')
    C_DEPT=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $5}')
    C_PHONE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $6}')
    C_MOBILE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $7}')
    C_EMAIL=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $8}')
    C_STREET=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $9}')
    C_CITY=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $10}')
    C_STATE=$(echo "$CONTACT_DATA" | awk -F'\t' '{print $11}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "contact_found": ${CONTACT_FOUND},
  "contact_id": "$(json_escape "${C_ID:-}")",
  "first_name": "$(json_escape "${C_FIRST:-}")",
  "last_name": "$(json_escape "${C_LAST:-}")",
  "title": "$(json_escape "${C_TITLE:-}")",
  "department": "$(json_escape "${C_DEPT:-}")",
  "phone_work": "$(json_escape "${C_PHONE:-}")",
  "phone_mobile": "$(json_escape "${C_MOBILE:-}")",
  "email": "$(json_escape "${C_EMAIL:-}")",
  "address_street": "$(json_escape "${C_STREET:-}")",
  "address_city": "$(json_escape "${C_CITY:-}")",
  "address_state": "$(json_escape "${C_STATE:-}")",
  "initial_count": ${INITIAL_CONTACT_COUNT},
  "current_count": ${CURRENT_CONTACT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_contact_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_contact_result.json"
echo "$RESULT_JSON"
echo "=== create_contact export complete ==="
