#!/bin/bash
echo "=== Exporting build_account_hierarchy results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/build_hierarchy_final.png

# 2. Get the initial state marker
INITIAL_MAX_CRMID=$(cat /tmp/initial_max_crmid.txt 2>/dev/null || echo "0")

# 3. Query Database for Parent Organization
P_DATA=$(vtiger_db_query "SELECT a.accountid, a.industry, a.annual_revenue FROM vtiger_account a JOIN vtiger_crmentity e ON a.accountid=e.crmid WHERE a.accountname='Apex Global Holdings' AND e.deleted=0 LIMIT 1")
P_FOUND="false"
if [ -n "$P_DATA" ]; then
    P_FOUND="true"
    P_ID=$(echo "$P_DATA" | awk -F'\t' '{print $1}')
    P_IND=$(echo "$P_DATA" | awk -F'\t' '{print $2}')
    P_REV=$(echo "$P_DATA" | awk -F'\t' '{print $3}')
fi

# 4. Query Database for Subsidiary 1
S1_DATA=$(vtiger_db_query "SELECT a.accountid, a.parentid FROM vtiger_account a JOIN vtiger_crmentity e ON a.accountid=e.crmid WHERE a.accountname='Apex Global - North America' AND e.deleted=0 LIMIT 1")
S1_FOUND="false"
if [ -n "$S1_DATA" ]; then
    S1_FOUND="true"
    S1_ID=$(echo "$S1_DATA" | awk -F'\t' '{print $1}')
    S1_PID=$(echo "$S1_DATA" | awk -F'\t' '{print $2}')
fi

# 5. Query Database for Subsidiary 2
S2_DATA=$(vtiger_db_query "SELECT a.accountid, a.parentid FROM vtiger_account a JOIN vtiger_crmentity e ON a.accountid=e.crmid WHERE a.accountname='Apex Global - EMEA' AND e.deleted=0 LIMIT 1")
S2_FOUND="false"
if [ -n "$S2_DATA" ]; then
    S2_FOUND="true"
    S2_ID=$(echo "$S2_DATA" | awk -F'\t' '{print $1}')
    S2_PID=$(echo "$S2_DATA" | awk -F'\t' '{print $2}')
fi

# 6. Query Database for Contact
C_DATA=$(vtiger_db_query "SELECT c.contactid, c.accountid, c.title FROM vtiger_contactdetails c JOIN vtiger_crmentity e ON c.contactid=e.crmid WHERE c.firstname='Elias' AND c.lastname='Vance' AND e.deleted=0 LIMIT 1")
C_FOUND="false"
if [ -n "$C_DATA" ]; then
    C_FOUND="true"
    C_ID=$(echo "$C_DATA" | awk -F'\t' '{print $1}')
    C_AID=$(echo "$C_DATA" | awk -F'\t' '{print $2}')
    C_TITLE=$(echo "$C_DATA" | awk -F'\t' '{print $3}')
fi

# 7. Construct Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "initial_max_crmid": ${INITIAL_MAX_CRMID},
  "parent": {
    "found": ${P_FOUND},
    "id": "${P_ID:-0}",
    "industry": "$(json_escape "${P_IND:-}")",
    "revenue": "${P_REV:-0}"
  },
  "sub1": {
    "found": ${S1_FOUND},
    "id": "${S1_ID:-0}",
    "parentid": "${S1_PID:-0}"
  },
  "sub2": {
    "found": ${S2_FOUND},
    "id": "${S2_ID:-0}",
    "parentid": "${S2_PID:-0}"
  },
  "contact": {
    "found": ${C_FOUND},
    "id": "${C_ID:-0}",
    "accountid": "${C_AID:-0}",
    "title": "$(json_escape "${C_TITLE:-}")"
  }
}
JSONEOF
)

# 8. Save output
safe_write_result "/tmp/build_hierarchy_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/build_hierarchy_result.json"
echo "$RESULT_JSON"
echo "=== build_account_hierarchy export complete ==="