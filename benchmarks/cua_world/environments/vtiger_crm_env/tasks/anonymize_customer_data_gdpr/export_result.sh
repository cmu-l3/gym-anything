#!/bin/bash
echo "=== Exporting anonymize_customer_data_gdpr results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/gdpr_final_state.png

# Read target IDs
if [ ! -f "/tmp/gdpr_target_ids.json" ]; then
    echo "ERROR: target IDs file missing!"
    exit 1
fi

LEAD_ID=$(python3 -c "import json; print(json.load(open('/tmp/gdpr_target_ids.json'))['lead_id'])")
CONTACT_ID=$(python3 -c "import json; print(json.load(open('/tmp/gdpr_target_ids.json'))['contact_id'])")

echo "Evaluating Lead $LEAD_ID and Contact $CONTACT_ID"

# 1. Check Deletion Status (Anti-Gaming)
LEAD_DELETED=$(vtiger_db_query "SELECT deleted FROM vtiger_crmentity WHERE crmid=$LEAD_ID" | tr -d '[:space:]')
CONTACT_DELETED=$(vtiger_db_query "SELECT deleted FROM vtiger_crmentity WHERE crmid=$CONTACT_ID" | tr -d '[:space:]')

# 2. Extract Lead Data
LEAD_FNAME=$(vtiger_db_query "SELECT firstname FROM vtiger_leaddetails WHERE leadid=$LEAD_ID" | tr -d '\n' | sed 's/\r//')
LEAD_LNAME=$(vtiger_db_query "SELECT lastname FROM vtiger_leaddetails WHERE leadid=$LEAD_ID" | tr -d '\n' | sed 's/\r//')
LEAD_EMAIL=$(vtiger_db_query "SELECT email FROM vtiger_leaddetails WHERE leadid=$LEAD_ID" | tr -d '\n' | sed 's/\r//')
LEAD_PHONE=$(vtiger_db_query "SELECT phone FROM vtiger_leaddetails WHERE leadid=$LEAD_ID" | tr -d '\n' | sed 's/\r//')
LEAD_OPTE=$(vtiger_db_query "SELECT emailoptout FROM vtiger_leaddetails WHERE leadid=$LEAD_ID" | tr -d '[:space:]')
LEAD_OPTC=$(vtiger_db_query "SELECT donotcall FROM vtiger_leaddetails WHERE leadid=$LEAD_ID" | tr -d '[:space:]')

# 3. Extract Contact Data
CONTACT_FNAME=$(vtiger_db_query "SELECT firstname FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_LNAME=$(vtiger_db_query "SELECT lastname FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_EMAIL=$(vtiger_db_query "SELECT email FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_PHONE=$(vtiger_db_query "SELECT phone FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_OPTE=$(vtiger_db_query "SELECT emailoptout FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID" | tr -d '[:space:]')
CONTACT_OPTC=$(vtiger_db_query "SELECT donotcall FROM vtiger_contactdetails WHERE contactid=$CONTACT_ID" | tr -d '[:space:]')

# 4. Extract Contact Address
CONTACT_STREET=$(vtiger_db_query "SELECT mailingstreet FROM vtiger_contactaddress WHERE contactaddressid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_CITY=$(vtiger_db_query "SELECT mailingcity FROM vtiger_contactaddress WHERE contactaddressid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_STATE=$(vtiger_db_query "SELECT mailingstate FROM vtiger_contactaddress WHERE contactaddressid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')
CONTACT_ZIP=$(vtiger_db_query "SELECT mailingzip FROM vtiger_contactaddress WHERE contactaddressid=$CONTACT_ID" | tr -d '\n' | sed 's/\r//')

# 5. Check Audit Comment
COMMENT_MATCHES=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_modcomments WHERE related_to=$CONTACT_ID AND commentcontent LIKE '%GDPR Right to be Forgotten executed%'" | tr -d '[:space:]')

RESULT_JSON=$(cat << JSONEOF
{
  "lead": {
    "deleted": "$(json_escape "${LEAD_DELETED:-1}")",
    "firstname": "$(json_escape "${LEAD_FNAME:-}")",
    "lastname": "$(json_escape "${LEAD_LNAME:-}")",
    "email": "$(json_escape "${LEAD_EMAIL:-}")",
    "phone": "$(json_escape "${LEAD_PHONE:-}")",
    "emailoptout": "$(json_escape "${LEAD_OPTE:-0}")",
    "donotcall": "$(json_escape "${LEAD_OPTC:-0}")"
  },
  "contact": {
    "deleted": "$(json_escape "${CONTACT_DELETED:-1}")",
    "firstname": "$(json_escape "${CONTACT_FNAME:-}")",
    "lastname": "$(json_escape "${CONTACT_LNAME:-}")",
    "email": "$(json_escape "${CONTACT_EMAIL:-}")",
    "phone": "$(json_escape "${CONTACT_PHONE:-}")",
    "emailoptout": "$(json_escape "${CONTACT_OPTE:-0}")",
    "donotcall": "$(json_escape "${CONTACT_OPTC:-0}")",
    "street": "$(json_escape "${CONTACT_STREET:-}")",
    "city": "$(json_escape "${CONTACT_CITY:-}")",
    "state": "$(json_escape "${CONTACT_STATE:-}")",
    "zip": "$(json_escape "${CONTACT_ZIP:-}")"
  },
  "audit_comment_count": ${COMMENT_MATCHES:-0}
}
JSONEOF
)

safe_write_result "/tmp/gdpr_result.json" "$RESULT_JSON"

echo "Result JSON written to /tmp/gdpr_result.json:"
cat /tmp/gdpr_result.json
echo "=== Export complete ==="