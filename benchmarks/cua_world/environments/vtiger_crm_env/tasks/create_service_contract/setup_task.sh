#!/bin/bash
set -e
echo "=== Setting up create_service_contract task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure prerequisite org and contact exist via Vtiger PHP API
cat > /tmp/setup_service_contract_prereqs.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html/vtigercrm');

$_SERVER['HTTP_HOST'] = 'localhost:8000';
$_SERVER['REQUEST_URI'] = '/index.php';
$_SERVER['SERVER_NAME'] = 'localhost';
$_SERVER['SERVER_PORT'] = '8000';
$_SERVER['DOCUMENT_ROOT'] = '/var/www/html/vtigercrm';

require_once('vendor/autoload.php');
include_once('config.inc.php');
include_once('include/utils/utils.php');
include_once('include/Loader.php');
vimport('includes.runtime.EntryPoint');

global $adb, $current_user;
$adb = PearDatabase::getInstance();
$adb->connect();

// Load admin user
$current_user = CRMEntity::getInstance('Users');
$current_user->retrieve_entity_info(1, 'Users');
$current_user->id = 1;

// Check if organization exists
$orgResult = $adb->pquery("SELECT accountid FROM vtiger_account WHERE accountname = ?", array('Riverside Property Management'));
if ($adb->num_rows($orgResult) == 0) {
    echo "Creating organization: Riverside Property Management\n";
    $org = CRMEntity::getInstance('Accounts');
    $org->column_fields['accountname'] = 'Riverside Property Management';
    $org->column_fields['industry'] = 'Real Estate';
    $org->column_fields['phone'] = '(503) 555-0147';
    $org->column_fields['bill_street'] = '4200 Riverside Drive';
    $org->column_fields['bill_city'] = 'Portland';
    $org->column_fields['bill_state'] = 'OR';
    $org->column_fields['bill_code'] = '97201';
    $org->column_fields['bill_country'] = 'United States';
    $org->column_fields['assigned_user_id'] = 1;
    $org->save('Accounts');
    $orgId = $org->id;
} else {
    $orgId = $adb->query_result($orgResult, 0, 'accountid');
}

// Check if contact exists
$conResult = $adb->pquery("SELECT contactid FROM vtiger_contactdetails WHERE firstname = ? AND lastname = ?", array('Diana', 'Mercer'));
if ($adb->num_rows($conResult) == 0) {
    echo "Creating contact: Diana Mercer\n";
    $con = CRMEntity::getInstance('Contacts');
    $con->column_fields['firstname'] = 'Diana';
    $con->column_fields['lastname'] = 'Mercer';
    $con->column_fields['email'] = 'diana.mercer@riversideprop.com';
    $con->column_fields['phone'] = '(503) 555-0198';
    $con->column_fields['title'] = 'Facilities Director';
    $con->column_fields['account_id'] = $orgId;
    $con->column_fields['assigned_user_id'] = 1;
    $con->save('Contacts');
    $contactId = $con->id;
} else {
    $contactId = $adb->query_result($conResult, 0, 'contactid');
}

// Save IDs for verification
file_put_contents('/tmp/riverside_org_id.txt', $orgId);
file_put_contents('/tmp/diana_contact_id.txt', $contactId);

echo "Prerequisites ready. Org ID: $orgId, Contact ID: $contactId\n";
?>
PHPEOF

docker cp /tmp/setup_service_contract_prereqs.php vtiger-app:/tmp/setup_service_contract_prereqs.php
docker exec vtiger-app php /tmp/setup_service_contract_prereqs.php

# Extract IDs from the container to local host
docker exec vtiger-app cat /tmp/riverside_org_id.txt > /tmp/riverside_org_id.txt 2>/dev/null || echo "" > /tmp/riverside_org_id.txt
docker exec vtiger-app cat /tmp/diana_contact_id.txt > /tmp/diana_contact_id.txt 2>/dev/null || echo "" > /tmp/diana_contact_id.txt

# Record initial service contract count
INITIAL_SC_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_servicecontracts sc JOIN vtiger_crmentity ce ON sc.servicecontractsid = ce.crmid WHERE ce.deleted = 0" | tr -d '[:space:]')
echo "$INITIAL_SC_COUNT" > /tmp/initial_sc_count.txt

# Log in and navigate to Service Contracts module
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=ServiceContracts&view=List"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="