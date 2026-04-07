#!/bin/bash
echo "=== Exporting configure_restricted_role_profile results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query database for created entities
PROFILE_ID=$(vtiger_db_query "SELECT profileid FROM vtiger_profile WHERE profilename='Restricted Sales' LIMIT 1" | tr -d '[:space:]')
ROLE_ID=$(vtiger_db_query "SELECT roleid FROM vtiger_role WHERE rolename='Junior Sales Rep' LIMIT 1" | tr -d '[:space:]')
SALES_MGR_ROLE_ID=$(vtiger_db_query "SELECT roleid FROM vtiger_role WHERE rolename='Sales Manager' LIMIT 1" | tr -d '[:space:]')

# Query permissions if profile exists
LEADS_DELETE_PERM=""
CONTACTS_DELETE_PERM=""

if [ -n "$PROFILE_ID" ]; then
    # Action ID 2 corresponds to 'Delete' operation
    LEADS_TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Leads' LIMIT 1" | tr -d '[:space:]')
    CONTACTS_TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Contacts' LIMIT 1" | tr -d '[:space:]')
    
    LEADS_DELETE_PERM=$(vtiger_db_query "SELECT permissions FROM vtiger_profile2standardpermissions WHERE profileid='$PROFILE_ID' AND tabid='$LEADS_TABID' AND Operation='2' LIMIT 1" | tr -d '[:space:]')
    CONTACTS_DELETE_PERM=$(vtiger_db_query "SELECT permissions FROM vtiger_profile2standardpermissions WHERE profileid='$PROFILE_ID' AND tabid='$CONTACTS_TABID' AND Operation='2' LIMIT 1" | tr -d '[:space:]')
fi

# Query role relationships if role exists
ROLE_PARENT=""
ROLE_PROFILE=""

if [ -n "$ROLE_ID" ]; then
    ROLE_PARENT=$(vtiger_db_query "SELECT parentrole FROM vtiger_role WHERE roleid='$ROLE_ID' LIMIT 1" | tr -d '[:space:]')
    ROLE_PROFILE=$(vtiger_db_query "SELECT profileid FROM vtiger_role2profile WHERE roleid='$ROLE_ID' LIMIT 1" | tr -d '[:space:]')
fi

# Determine boolean flags
PROFILE_EXISTS="false"
ROLE_EXISTS="false"
if [ -n "$PROFILE_ID" ]; then PROFILE_EXISTS="true"; fi
if [ -n "$ROLE_ID" ]; then ROLE_EXISTS="true"; fi

# Write out JSON
RESULT_JSON=$(cat << JSONEOF
{
  "profile_exists": $PROFILE_EXISTS,
  "profile_id": "$(json_escape "${PROFILE_ID:-}")",
  "role_exists": $ROLE_EXISTS,
  "role_id": "$(json_escape "${ROLE_ID:-}")",
  "sales_mgr_role_id": "$(json_escape "${SALES_MGR_ROLE_ID:-}")",
  "leads_delete_permission": "$(json_escape "${LEADS_DELETE_PERM:-}")",
  "contacts_delete_permission": "$(json_escape "${CONTACTS_DELETE_PERM:-}")",
  "role_parent_hierarchy": "$(json_escape "${ROLE_PARENT:-}")",
  "role_assigned_profile": "$(json_escape "${ROLE_PROFILE:-}")",
  "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
  "export_time": $(date +%s)
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="