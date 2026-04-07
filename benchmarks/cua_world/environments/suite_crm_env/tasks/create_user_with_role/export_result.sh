#!/bin/bash
echo "=== Exporting create_user_with_role results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load initial counts
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_USER_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM users WHERE deleted=0" | tr -d '[:space:]' || echo "0")
CURRENT_ROLE_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM acl_roles WHERE deleted=0" | tr -d '[:space:]' || echo "0")

# 1. Gather Role Data
ROLE_ID=$(suitecrm_db_query "SELECT id FROM acl_roles WHERE name='Field Sales Rep' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
ROLE_FOUND="false"
ACCT_DEL_PERM=""
ACCT_EXP_PERM=""
CASE_ACC_PERM=""

if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "NULL" ]; then
    ROLE_FOUND="true"
    
    # Get permissions
    ACCT_DEL_PERM=$(suitecrm_db_query "SELECT ara.access_override FROM acl_roles_actions ara JOIN acl_actions aa ON ara.action_id=aa.id WHERE ara.role_id='$ROLE_ID' AND aa.category='Accounts' AND aa.name='delete' AND aa.acltype='module' AND ara.deleted=0 LIMIT 1" | tr -d '[:space:]')
    
    ACCT_EXP_PERM=$(suitecrm_db_query "SELECT ara.access_override FROM acl_roles_actions ara JOIN acl_actions aa ON ara.action_id=aa.id WHERE ara.role_id='$ROLE_ID' AND aa.category='Accounts' AND aa.name='export' AND aa.acltype='module' AND ara.deleted=0 LIMIT 1" | tr -d '[:space:]')
    
    CASE_ACC_PERM=$(suitecrm_db_query "SELECT ara.access_override FROM acl_roles_actions ara JOIN acl_actions aa ON ara.action_id=aa.id WHERE ara.role_id='$ROLE_ID' AND aa.category='Cases' AND aa.name='access' AND aa.acltype='module' AND ara.deleted=0 LIMIT 1" | tr -d '[:space:]')
fi

# 2. Gather User Data
USER_DATA=$(suitecrm_db_query "SELECT id, first_name, last_name, status FROM users WHERE user_name='mchen' AND deleted=0 LIMIT 1")
USER_FOUND="false"
U_ID=""
U_FIRST=""
U_LAST=""
U_STATUS=""
U_EMAIL=""

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    U_ID=$(echo "$USER_DATA" | awk -F'\t' '{print $1}')
    U_FIRST=$(echo "$USER_DATA" | awk -F'\t' '{print $2}')
    U_LAST=$(echo "$USER_DATA" | awk -F'\t' '{print $3}')
    U_STATUS=$(echo "$USER_DATA" | awk -F'\t' '{print $4}')
    
    # Get Email
    U_EMAIL=$(suitecrm_db_query "SELECT ea.email_address FROM email_addresses ea JOIN email_addr_bean_rel eabr ON ea.id=eabr.email_address_id WHERE eabr.bean_id='$U_ID' AND eabr.bean_module='Users' AND eabr.deleted=0 AND ea.deleted=0 LIMIT 1" | tr -d '[:space:]')
fi

# 3. Gather Relationship Data
ROLE_ASSIGNED="false"
if [ "$ROLE_FOUND" = "true" ] && [ "$USER_FOUND" = "true" ]; then
    LINK_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM acl_roles_users WHERE role_id='$ROLE_ID' AND user_id='$U_ID' AND deleted=0" | tr -d '[:space:]')
    if [ -n "$LINK_COUNT" ] && [ "$LINK_COUNT" -gt 0 ] 2>/dev/null; then
        ROLE_ASSIGNED="true"
    fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

RESULT_JSON=$(cat << JSONEOF
{
  "role_found": ${ROLE_FOUND},
  "role_id": "$(json_escape "${ROLE_ID:-}")",
  "acct_delete_perm": "$(json_escape "${ACCT_DEL_PERM:-}")",
  "acct_export_perm": "$(json_escape "${ACCT_EXP_PERM:-}")",
  "case_access_perm": "$(json_escape "${CASE_ACC_PERM:-}")",
  
  "user_found": ${USER_FOUND},
  "user_id": "$(json_escape "${U_ID:-}")",
  "first_name": "$(json_escape "${U_FIRST:-}")",
  "last_name": "$(json_escape "${U_LAST:-}")",
  "status": "$(json_escape "${U_STATUS:-}")",
  "email": "$(json_escape "${U_EMAIL:-}")",
  
  "role_assigned_to_user": ${ROLE_ASSIGNED},
  
  "initial_user_count": ${INITIAL_USER_COUNT},
  "current_user_count": ${CURRENT_USER_COUNT},
  "initial_role_count": ${INITIAL_ROLE_COUNT},
  "current_role_count": ${CURRENT_ROLE_COUNT},
  
  "app_was_running": ${APP_RUNNING}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="