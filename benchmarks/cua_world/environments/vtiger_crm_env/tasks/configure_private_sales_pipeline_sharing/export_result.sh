#!/bin/bash
echo "=== Exporting configure_private_sales_pipeline_sharing results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check the database for the new sharing configurations
echo "Querying database for Sharing Access configurations..."

# Get Potentials tabid
POTENTIALS_TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Potentials' LIMIT 1" | tr -d '[:space:]')

# Check Org-wide default permission for Potentials (0=Public, 3=Private)
ORG_SHARE_PERM=$(vtiger_db_query "SELECT permission FROM vtiger_def_org_share WHERE tabid=$POTENTIALS_TABID LIMIT 1" | tr -d '[:space:]')
if [ -z "$ORG_SHARE_PERM" ]; then
    ORG_SHARE_PERM="-1"
fi

# Check if the specific custom sharing rule exists
CUSTOM_RULE_COUNT=$(vtiger_db_query "
SELECT count(*) FROM vtiger_datashare_role2role r2r
JOIN vtiger_datashare_module_rel mrel ON r2r.shareid = mrel.shareid
JOIN vtiger_tab t ON t.tabid = mrel.tabid
JOIN vtiger_role r_from ON r_from.roleid = r2r.share_roleid
JOIN vtiger_role r_to ON r_to.roleid = r2r.to_roleid
WHERE t.name = 'Potentials'
AND r_from.rolename = 'Sales Person'
AND r_to.rolename = 'Sales Manager'
" | tr -d '[:space:]')

if [ -z "$CUSTOM_RULE_COUNT" ]; then
    CUSTOM_RULE_COUNT="0"
fi

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Export to JSON
RESULT_JSON=$(cat << JSONEOF
{
  "potentials_tabid": ${POTENTIALS_TABID:-0},
  "org_share_permission": ${ORG_SHARE_PERM},
  "custom_rule_count": ${CUSTOM_RULE_COUNT},
  "task_start": ${TASK_START},
  "task_end": ${TASK_END}
}
JSONEOF
)

safe_write_result "/tmp/sharing_config_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/sharing_config_result.json"
echo "$RESULT_JSON"
echo "=== configure_private_sales_pipeline_sharing export complete ==="