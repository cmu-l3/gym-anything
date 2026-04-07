#!/bin/bash
echo "=== Setting up configure_restricted_role_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing attempts to ensure idempotency
echo "Cleaning up any existing test records..."
OLD_ROLE=$(vtiger_db_query "SELECT roleid FROM vtiger_role WHERE rolename='Junior Sales Rep' LIMIT 1" | tr -d '[:space:]')
if [ -n "$OLD_ROLE" ]; then
    vtiger_db_query "DELETE FROM vtiger_role WHERE roleid='$OLD_ROLE'"
    vtiger_db_query "DELETE FROM vtiger_role2profile WHERE roleid='$OLD_ROLE'"
    echo "Removed old role: $OLD_ROLE"
fi

OLD_PROFILE=$(vtiger_db_query "SELECT profileid FROM vtiger_profile WHERE profilename='Restricted Sales' LIMIT 1" | tr -d '[:space:]')
if [ -n "$OLD_PROFILE" ]; then
    vtiger_db_query "DELETE FROM vtiger_profile WHERE profileid='$OLD_PROFILE'"
    vtiger_db_query "DELETE FROM vtiger_profile2standardpermissions WHERE profileid='$OLD_PROFILE'"
    vtiger_db_query "DELETE FROM vtiger_profile2globalpermissions WHERE profileid='$OLD_PROFILE'"
    vtiger_db_query "DELETE FROM vtiger_profile2tab WHERE profileid='$OLD_PROFILE'"
    echo "Removed old profile: $OLD_PROFILE"
fi

# 2. Ensure logged in and navigate to CRM Settings -> Profiles
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Profiles&parent=Settings&view=List"
sleep 3

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== configure_restricted_role_profile task setup complete ==="