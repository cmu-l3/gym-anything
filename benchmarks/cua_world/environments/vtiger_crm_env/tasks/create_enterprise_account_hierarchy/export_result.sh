#!/bin/bash
echo "=== Exporting create_enterprise_account_hierarchy results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Querying database for created records..."

# Query Parent Organization
P_ORG=$(vtiger_db_query "SELECT a.accountid, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_account a JOIN vtiger_crmentity e ON a.accountid=e.crmid WHERE a.accountname='AeroTech Dynamics Global HQ' AND e.deleted=0 ORDER BY a.accountid DESC LIMIT 1")
PO_ID=$(echo "$P_ORG" | awk -F'\t' '{print $1}')
PO_TIME=$(echo "$P_ORG" | awk -F'\t' '{print $2}')

# Query EU Organization
EU_ORG=$(vtiger_db_query "SELECT a.accountid, a.parentid, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_account a JOIN vtiger_crmentity e ON a.accountid=e.crmid WHERE a.accountname='AeroTech Dynamics GmbH' AND e.deleted=0 ORDER BY a.accountid DESC LIMIT 1")
EU_ID=$(echo "$EU_ORG" | awk -F'\t' '{print $1}')
EU_PARENT=$(echo "$EU_ORG" | awk -F'\t' '{print $2}')
EU_TIME=$(echo "$EU_ORG" | awk -F'\t' '{print $3}')

# Query APAC Organization
APAC_ORG=$(vtiger_db_query "SELECT a.accountid, a.parentid, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_account a JOIN vtiger_crmentity e ON a.accountid=e.crmid WHERE a.accountname='AeroTech Dynamics KK' AND e.deleted=0 ORDER BY a.accountid DESC LIMIT 1")
APAC_ID=$(echo "$APAC_ORG" | awk -F'\t' '{print $1}')
APAC_PARENT=$(echo "$APAC_ORG" | awk -F'\t' '{print $2}')
APAC_TIME=$(echo "$APAC_ORG" | awk -F'\t' '{print $3}')

# Query EU Contact
EU_CONT=$(vtiger_db_query "SELECT c.contactid, c.accountid, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_contactdetails c JOIN vtiger_crmentity e ON c.contactid=e.crmid WHERE c.firstname='Klaus' AND c.lastname='Wagner' AND e.deleted=0 ORDER BY c.contactid DESC LIMIT 1")
EUC_ID=$(echo "$EU_CONT" | awk -F'\t' '{print $1}')
EUC_ORG=$(echo "$EU_CONT" | awk -F'\t' '{print $2}')
EUC_TIME=$(echo "$EU_CONT" | awk -F'\t' '{print $3}')

# Query APAC Contact
APAC_CONT=$(vtiger_db_query "SELECT c.contactid, c.accountid, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_contactdetails c JOIN vtiger_crmentity e ON c.contactid=e.crmid WHERE c.firstname='Yuki' AND c.lastname='Tanaka' AND e.deleted=0 ORDER BY c.contactid DESC LIMIT 1")
APACC_ID=$(echo "$APAC_CONT" | awk -F'\t' '{print $1}')
APACC_ORG=$(echo "$APAC_CONT" | awk -F'\t' '{print $2}')
APACC_TIME=$(echo "$APAC_CONT" | awk -F'\t' '{print $3}')

# Query Global Deal
DEAL_RES=$(vtiger_db_query "SELECT p.potentialid, p.related_to, p.amount, p.sales_stage, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_potential p JOIN vtiger_crmentity e ON p.potentialid=e.crmid WHERE p.potentialname='Q4 2026 Commercial Aviation Parts Contract' AND e.deleted=0 ORDER BY p.potentialid DESC LIMIT 1")
DEAL_ID=$(echo "$DEAL_RES" | awk -F'\t' '{print $1}')
DEAL_RELATED=$(echo "$DEAL_RES" | awk -F'\t' '{print $2}')
DEAL_AMOUNT=$(echo "$DEAL_RES" | awk -F'\t' '{print $3}')
DEAL_STAGE=$(echo "$DEAL_RES" | awk -F'\t' '{print $4}')
DEAL_TIME=$(echo "$DEAL_RES" | awk -F'\t' '{print $5}')

# Construct JSON result
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START:-0},
  "parent_org": {
    "id": "$(json_escape "${PO_ID:-}")",
    "created_time": $([ -n "$PO_TIME" ] && echo "$PO_TIME" || echo "0")
  },
  "eu_org": {
    "id": "$(json_escape "${EU_ID:-}")",
    "parent_id": "$(json_escape "${EU_PARENT:-}")",
    "created_time": $([ -n "$EU_TIME" ] && echo "$EU_TIME" || echo "0")
  },
  "apac_org": {
    "id": "$(json_escape "${APAC_ID:-}")",
    "parent_id": "$(json_escape "${APAC_PARENT:-}")",
    "created_time": $([ -n "$APAC_TIME" ] && echo "$APAC_TIME" || echo "0")
  },
  "eu_contact": {
    "id": "$(json_escape "${EUC_ID:-}")",
    "org_id": "$(json_escape "${EUC_ORG:-}")",
    "created_time": $([ -n "$EUC_TIME" ] && echo "$EUC_TIME" || echo "0")
  },
  "apac_contact": {
    "id": "$(json_escape "${APACC_ID:-}")",
    "org_id": "$(json_escape "${APACC_ORG:-}")",
    "created_time": $([ -n "$APACC_TIME" ] && echo "$APACC_TIME" || echo "0")
  },
  "deal": {
    "id": "$(json_escape "${DEAL_ID:-}")",
    "org_id": "$(json_escape "${DEAL_RELATED:-}")",
    "amount": "$(json_escape "${DEAL_AMOUNT:-}")",
    "stage": "$(json_escape "${DEAL_STAGE:-}")",
    "created_time": $([ -n "$DEAL_TIME" ] && echo "$DEAL_TIME" || echo "0")
  }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="