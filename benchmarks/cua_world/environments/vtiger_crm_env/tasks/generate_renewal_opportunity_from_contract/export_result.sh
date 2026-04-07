#!/bin/bash
echo "=== Exporting generate_renewal_opportunity_from_contract results ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# 1. Dynamically retrieve the ground-truth target (contract with earliest due_date)
TARGET_SQL="SELECT s.servicecontractsid, s.subject, s.due_date, s.sc_related_to, a.accountname \
            FROM vtiger_servicecontracts s \
            JOIN vtiger_crmentity e ON s.servicecontractsid = e.crmid \
            LEFT JOIN vtiger_account a ON s.sc_related_to = a.accountid \
            WHERE e.deleted = 0 \
            ORDER BY s.due_date ASC LIMIT 1"

TARGET_DATA=$(vtiger_db_query "$TARGET_SQL")

T_ID=$(echo "$TARGET_DATA" | awk -F'\t' '{print $1}')
T_SUBJ=$(echo "$TARGET_DATA" | awk -F'\t' '{print $2}')
T_DUE=$(echo "$TARGET_DATA" | awk -F'\t' '{print $3}')
T_ORG_ID=$(echo "$TARGET_DATA" | awk -F'\t' '{print $4}')
T_ORG_NAME=$(echo "$TARGET_DATA" | awk -F'\t' '{print $5}')

# 2. Retrieve the most recent Opportunity created by the agent
INITIAL_MAX_OPP_ID=$(cat /tmp/initial_max_opp_id.txt 2>/dev/null || echo "0")

OPP_SQL="SELECT p.potentialid, p.potentialname, p.amount, p.closingdate, p.sales_stage, p.related_to \
         FROM vtiger_potential p \
         JOIN vtiger_crmentity e ON p.potentialid = e.crmid \
         WHERE e.deleted = 0 AND p.potentialid > $INITIAL_MAX_OPP_ID \
         ORDER BY p.potentialid DESC LIMIT 1"

OPP_DATA=$(vtiger_db_query "$OPP_SQL")

OPP_FOUND="false"
if [ -n "$OPP_DATA" ]; then
    OPP_FOUND="true"
    O_ID=$(echo "$OPP_DATA" | awk -F'\t' '{print $1}')
    O_NAME=$(echo "$OPP_DATA" | awk -F'\t' '{print $2}')
    O_AMOUNT=$(echo "$OPP_DATA" | awk -F'\t' '{print $3}')
    O_CLOSE=$(echo "$OPP_DATA" | awk -F'\t' '{print $4}')
    O_STAGE=$(echo "$OPP_DATA" | awk -F'\t' '{print $5}')
    O_ORG_ID=$(echo "$OPP_DATA" | awk -F'\t' '{print $6}')
fi

# 3. Look for the requested audit comment directly on the targeted Service Contract
COMMENT_SQL="SELECT c.commentcontent \
             FROM vtiger_modcomments c \
             JOIN vtiger_crmentity e ON c.modcommentsid = e.crmid \
             WHERE c.related_to = ${T_ID} AND e.deleted = 0 \
             ORDER BY e.createdtime DESC LIMIT 1"

COMMENT_DATA=$(vtiger_db_query "$COMMENT_SQL")

COMMENT_FOUND="false"
if [ -n "$COMMENT_DATA" ]; then
    COMMENT_FOUND="true"
    C_CONTENT=$(echo "$COMMENT_DATA" | tr '\n' ' ' | tr '\r' ' ') # Strip newlines
fi

RESULT_JSON=$(cat << JSONEOF
{
  "target_contract": {
    "id": "$(json_escape "${T_ID:-}")",
    "subject": "$(json_escape "${T_SUBJ:-}")",
    "due_date": "$(json_escape "${T_DUE:-}")",
    "org_id": "$(json_escape "${T_ORG_ID:-}")",
    "org_name": "$(json_escape "${T_ORG_NAME:-}")"
  },
  "new_opportunity": {
    "found": ${OPP_FOUND},
    "id": "$(json_escape "${O_ID:-}")",
    "name": "$(json_escape "${O_NAME:-}")",
    "amount": "$(json_escape "${O_AMOUNT:-}")",
    "close_date": "$(json_escape "${O_CLOSE:-}")",
    "stage": "$(json_escape "${O_STAGE:-}")",
    "org_id": "$(json_escape "${O_ORG_ID:-}")"
  },
  "target_comment": {
    "found": ${COMMENT_FOUND},
    "content": "$(json_escape "${C_CONTENT:-}")"
  }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "=== Export complete ==="