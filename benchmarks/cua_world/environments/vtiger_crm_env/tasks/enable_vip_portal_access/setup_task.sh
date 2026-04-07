#!/bin/bash
echo "=== Setting up enable_vip_portal_access task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Bootstrapping initial data state via Vtiger PHP API
# This securely ensures Elena Rostova exists with default/old values so the agent can update them
cat > /tmp/prep_contact.php << 'PHPEOF'
<?php
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';
$user = Users::getActiveAdminUser();
vglobal('current_user', $user);

global $adb;
// Check if Elena already exists
$result = $adb->pquery("SELECT contactid FROM vtiger_contactdetails WHERE firstname=? AND lastname=?", array('Elena', 'Rostova'));
if ($adb->num_rows($result) > 0) {
    $recordId = $adb->query_result($result, 0, 'contactid');
    $recordModel = Vtiger_Record_Model::getInstanceById($recordId, 'Contacts');
} else {
    $recordModel = Vtiger_Record_Model::getCleanInstance('Contacts');
    $recordModel->set('firstname', 'Elena');
    $recordModel->set('lastname', 'Rostova');
    $recordModel->set('assigned_user_id', $user->id);
}

// Reset fields to an unconfigured state
$recordModel->set('title', 'Manager'); 
$recordModel->set('department', 'Operations'); 
$recordModel->set('portal', 0);
$recordModel->set('support_start_date', '');
$recordModel->set('support_end_date', '');
$recordModel->save();

echo "CRM_ID:" . $recordModel->getId() . "\n";
?>
PHPEOF

echo "Preparing target contact record..."
docker cp /tmp/prep_contact.php vtiger-app:/tmp/prep_contact.php
ELENA_CRM_ID=$(docker exec vtiger-app php /tmp/prep_contact.php | grep "CRM_ID:" | cut -d':' -f2)
echo "Elena Rostova CRM ID configured as: $ELENA_CRM_ID"

# 3. Clean up any existing tickets with the target name to ensure fresh state
EXISTING_TICKET=$(vtiger_db_query "SELECT ticketid FROM vtiger_troubletickets WHERE title='VIP Onboarding - Elena Rostova' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_TICKET" ]; then
    echo "Cleaning up existing target ticket..."
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_TICKET"
    vtiger_db_query "DELETE FROM vtiger_troubletickets WHERE ticketid=$EXISTING_TICKET"
fi

# 4. Record initial ticket count
INITIAL_TICKET_COUNT=$(get_ticket_count)
echo "$INITIAL_TICKET_COUNT" > /tmp/initial_ticket_count.txt

# 5. Ensure Firefox is open, logged in, and at the home dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== enable_vip_portal_access task setup complete ==="