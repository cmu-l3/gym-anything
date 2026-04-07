#!/bin/bash
set -e
echo "=== Setting up Convert Lead task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Create the lead record via Vtiger PHP API
# ---------------------------------------------------------------
echo "--- Preparing lead record ---"

cat > /tmp/create_lead.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
ini_set('memory_limit', '256M');

chdir('/var/www/html/vtigercrm');

$_SERVER['HTTP_HOST'] = 'localhost:8000';
$_SERVER['REQUEST_URI'] = '/index.php';
$_SERVER['SERVER_NAME'] = 'localhost';
$_SERVER['SERVER_PORT'] = '8000';
$_SERVER['DOCUMENT_ROOT'] = '/var/www/html/vtigercrm';

require_once('vendor/autoload.php');
include_once('config.inc.php');
include_once('vtlib/Vtiger/Module.php');
include_once('include/utils/utils.php');
include_once('include/Loader.php');
vimport('includes.runtime.EntryPoint');

global $adb, $current_user;
$adb = PearDatabase::getInstance();
$adb->connect();

// Load admin user
$current_user = CRMEntity::getInstance('Users');
$current_user->retrieve_entity_info(1, 'Users');

// Remove existing targets to ensure a clean state
$adb->pquery("UPDATE vtiger_crmentity SET deleted=1 WHERE setype='Leads' AND label LIKE '%Patricia Hernandez%'", array());
$adb->pquery("UPDATE vtiger_crmentity SET deleted=1 WHERE setype='Contacts' AND label LIKE '%Patricia Hernandez%'", array());
$adb->pquery("UPDATE vtiger_crmentity SET deleted=1 WHERE setype='Accounts' AND label LIKE '%Summit Industrial%'", array());
$adb->pquery("UPDATE vtiger_crmentity SET deleted=1 WHERE setype='Potentials' AND label LIKE '%Summit Industrial%'", array());

echo "Cleaned up pre-existing records.\n";

// Create the Lead record
$lead = CRMEntity::getInstance('Leads');
$lead->column_fields['firstname'] = 'Patricia';
$lead->column_fields['lastname'] = 'Hernandez';
$lead->column_fields['company'] = 'Summit Industrial Supplies';
$lead->column_fields['designation'] = 'Procurement Director';
$lead->column_fields['email'] = 'p.hernandez@summitindustrial.com';
$lead->column_fields['phone'] = '312-555-0184';
$lead->column_fields['industry'] = 'Manufacturing';
$lead->column_fields['leadsource'] = 'Trade Show';
$lead->column_fields['leadstatus'] = 'Hot';
$lead->column_fields['annualrevenue'] = '12000000';
$lead->column_fields['noofemployees'] = '350';
$lead->column_fields['description'] = 'Met at Chicago Industrial Trade Show 2024. Interested in bulk fastener supply contract for their manufacturing facilities. Ready for conversion.';
$lead->column_fields['assigned_user_id'] = 1;

$lead->save('Leads');
$leadId = $lead->id;

echo "Lead created successfully with ID: $leadId\n";
?>
PHPEOF

docker cp /tmp/create_lead.php vtiger-app:/tmp/create_lead.php
docker exec vtiger-app php /tmp/create_lead.php 2>&1

# ---------------------------------------------------------------
# 2. Record Initial State
# ---------------------------------------------------------------
echo "--- Recording initial state ---"
INITIAL_CONTACT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails cd INNER JOIN vtiger_crmentity ce ON ce.crmid=cd.contactid WHERE ce.deleted=0" | tr -d '[:space:]')
INITIAL_ORG_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_account a INNER JOIN vtiger_crmentity ce ON ce.crmid=a.accountid WHERE ce.deleted=0" | tr -d '[:space:]')
INITIAL_POT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_potential p INNER JOIN vtiger_crmentity ce ON ce.crmid=p.potentialid WHERE ce.deleted=0" | tr -d '[:space:]')

echo "$INITIAL_CONTACT_COUNT" > /tmp/initial_contact_count.txt
echo "$INITIAL_ORG_COUNT" > /tmp/initial_org_count.txt
echo "$INITIAL_POT_COUNT" > /tmp/initial_pot_count.txt

# ---------------------------------------------------------------
# 3. Start Application & Navigate
# ---------------------------------------------------------------
echo "--- Launching Vtiger ---"
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Leads&view=List"
sleep 5

focus_firefox
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="