#!/bin/bash
echo "=== Setting up generate_renewal_opportunity_from_contract task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# Seed CRM with structured diverse data using Vtiger PHP APIs
# We create 3 distinct Orgs and 3 Service Contracts with different Due Dates
cat > /tmp/seed_contracts.php << 'PHPEOF'
<?php
error_reporting(E_ERROR | E_PARSE);
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';
$current_user = Users::getActiveAdminUser();

// Accounts
$a1 = Vtiger_Record_Model::getCleanInstance('Accounts');
$a1->set('accountname', 'TechCorp Solutions');
$a1->set('assigned_user_id', $current_user->id);
$a1->save();

$a2 = Vtiger_Record_Model::getCleanInstance('Accounts');
$a2->set('accountname', 'Global Logistics Inc');
$a2->set('assigned_user_id', $current_user->id);
$a2->save();

$a3 = Vtiger_Record_Model::getCleanInstance('Accounts');
$a3->set('accountname', 'Stark Industries');
$a3->set('assigned_user_id', $current_user->id);
$a3->save();

// Service Contracts
$sc1 = Vtiger_Record_Model::getCleanInstance('ServiceContracts');
$sc1->set('subject', 'Standard Support - TechCorp');
$sc1->set('sc_related_to', $a1->getId());
$sc1->set('contract_status', 'Active');
$sc1->set('start_date', date('Y-m-d', strtotime('-1 month')));
$sc1->set('due_date', date('Y-m-d', strtotime('+45 days'))); // Middle expiration
$sc1->set('assigned_user_id', $current_user->id);
$sc1->save();

$sc2 = Vtiger_Record_Model::getCleanInstance('ServiceContracts');
$sc2->set('subject', 'Premium SLA - Global Logistics');
$sc2->set('sc_related_to', $a2->getId());
$sc2->set('contract_status', 'Active');
$sc2->set('start_date', date('Y-m-d', strtotime('-6 months')));
$sc2->set('due_date', date('Y-m-d', strtotime('+20 days'))); // Earliest expiration (Target!)
$sc2->set('assigned_user_id', $current_user->id);
$sc2->save();

$sc3 = Vtiger_Record_Model::getCleanInstance('ServiceContracts');
$sc3->set('subject', 'Basic Maintenance - Stark');
$sc3->set('sc_related_to', $a3->getId());
$sc3->set('contract_status', 'Active');
$sc3->set('start_date', date('Y-m-d', strtotime('-2 months')));
$sc3->set('due_date', date('Y-m-d', strtotime('+80 days'))); // Latest expiration
$sc3->set('assigned_user_id', $current_user->id);
$sc3->save();
?>
PHPEOF
docker cp /tmp/seed_contracts.php vtiger-app:/tmp/seed_contracts.php
docker exec vtiger-app php /tmp/seed_contracts.php 2>/dev/null || true

# Capture the max opportunity ID prior to task to track what the agent creates
INITIAL_MAX_OPP_ID=$(vtiger_db_query "SELECT MAX(potentialid) FROM vtiger_potential" | tr -d '[:space:]')
if [ -z "$INITIAL_MAX_OPP_ID" ] || [ "$INITIAL_MAX_OPP_ID" = "NULL" ]; then
    INITIAL_MAX_OPP_ID=0
fi
echo "$INITIAL_MAX_OPP_ID" > /tmp/initial_max_opp_id.txt

# Ensure we're logged in and navigated directly to the Service Contracts module
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=ServiceContracts&view=List"
sleep 3

# Take initial screenshot showing the initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="