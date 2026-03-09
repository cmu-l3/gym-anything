#!/bin/bash
set -e
echo "=== Setting up account_dedup_consolidation task ==="

source /workspace/scripts/task_utils.sh

# 0. Record timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Record baseline
echo "--- Recording baseline ---"
suitecrm_db_query "SELECT id, name, account_type FROM accounts WHERE deleted=0 ORDER BY name" > /tmp/adc_baseline_accounts.txt
chmod 666 /tmp/adc_baseline_accounts.txt

# Get canonical account IDs
BOEING_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Boeing Company' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
GE_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='General Electric Company' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
echo "$BOEING_ID" > /tmp/adc_boeing_canonical_id.txt
echo "$GE_ID" > /tmp/adc_ge_canonical_id.txt
chmod 666 /tmp/adc_boeing_canonical_id.txt /tmp/adc_ge_canonical_id.txt

# 2. Create duplicate accounts with related records via PHP
cat > /tmp/adc_seed.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html');
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

$ids = [];

// --- Boeing duplicates ---
// Duplicate 1: "Boeing Co."
$b1 = BeanFactory::newBean('Accounts');
$b1->name = 'Boeing Co.';
$b1->industry = 'Manufacturing';
$b1->account_type = 'Customer';
$b1->phone_office = '(703) 465-3500';
$b1->billing_address_city = 'Arlington';
$b1->billing_address_state = 'VA';
$b1->billing_address_country = 'USA';
$b1->description = 'Aerospace and defense - imported from legacy ERP.';
$b1->save();
$ids['boeing_dup1'] = $b1->id;
echo "DUP_ACCT:" . $b1->id . ":Boeing Co.\n";

// Contact under Boeing Co.
$c1 = BeanFactory::newBean('Contacts');
$c1->first_name = 'Mark';
$c1->last_name = 'Richardson';
$c1->title = 'Supply Chain Analyst';
$c1->department = 'Supply Chain';
$c1->phone_work = '(703) 465-3560';
$c1->email1 = 'm.richardson@boeing.com';
$c1->account_id = $b1->id;
$c1->save();
echo "DUP_CONTACT:" . $c1->id . ":Mark Richardson\n";

// Opportunity under Boeing Co.
$o1 = BeanFactory::newBean('Opportunities');
$o1->name = 'Boeing - Avionics Test Automation';
$o1->amount = '1200000';
$o1->sales_stage = 'Proposal/Price Quote';
$o1->probability = '65';
$o1->date_closed = '2026-06-15';
$o1->account_id = $b1->id;
$o1->description = 'Automated testing platform for avionics systems certification.';
$o1->save();
echo "DUP_OPP:" . $o1->id . ":Boeing - Avionics Test Automation\n";

// Duplicate 2: "The Boeing Company"
$b2 = BeanFactory::newBean('Accounts');
$b2->name = 'The Boeing Company';
$b2->industry = 'Manufacturing';
$b2->account_type = 'Customer';
$b2->phone_office = '(703) 465-3500';
$b2->billing_address_city = 'Arlington';
$b2->billing_address_state = 'VA';
$b2->billing_address_country = 'USA';
$b2->description = 'Commercial and defense aviation. Duplicate from partner channel import.';
$b2->save();
$ids['boeing_dup2'] = $b2->id;
echo "DUP_ACCT:" . $b2->id . ":The Boeing Company\n";

// Contact under The Boeing Company
$c2 = BeanFactory::newBean('Contacts');
$c2->first_name = 'Sandra';
$c2->last_name = 'Mitchell';
$c2->title = 'Quality Systems Manager';
$c2->department = 'Quality Assurance';
$c2->phone_work = '(703) 465-3590';
$c2->email1 = 's.mitchell@boeing.com';
$c2->account_id = $b2->id;
$c2->save();
echo "DUP_CONTACT:" . $c2->id . ":Sandra Mitchell\n";

// --- GE duplicates ---
// Duplicate 1: "GE Company"
$g1 = BeanFactory::newBean('Accounts');
$g1->name = 'GE Company';
$g1->industry = 'Engineering';
$g1->account_type = 'Customer';
$g1->phone_office = '(617) 443-3000';
$g1->billing_address_city = 'Evendale';
$g1->billing_address_state = 'OH';
$g1->billing_address_country = 'USA';
$g1->description = 'General Electric - imported from marketing automation platform.';
$g1->save();
echo "DUP_ACCT:" . $g1->id . ":GE Company\n";

// Contact under GE Company
$c3 = BeanFactory::newBean('Contacts');
$c3->first_name = 'Jason';
$c3->last_name = 'Park';
$c3->title = 'Digital Innovation Lead';
$c3->department = 'Digital Technology';
$c3->phone_work = '(617) 443-3100';
$c3->email1 = 'j.park@ge.com';
$c3->account_id = $g1->id;
$c3->save();
echo "DUP_CONTACT:" . $c3->id . ":Jason Park\n";

// Opportunity under GE Company
$o2 = BeanFactory::newBean('Opportunities');
$o2->name = 'GE - Turbine Monitoring AI';
$o2->amount = '890000';
$o2->sales_stage = 'Needs Analysis';
$o2->probability = '25';
$o2->date_closed = '2026-08-30';
$o2->account_id = $g1->id;
$o2->description = 'AI-powered turbine blade inspection and predictive maintenance system.';
$o2->save();
echo "DUP_OPP:" . $o2->id . ":GE - Turbine Monitoring AI\n";

// Duplicate 2: "General Electric Co"
$g2 = BeanFactory::newBean('Accounts');
$g2->name = 'General Electric Co';
$g2->industry = 'Engineering';
$g2->account_type = 'Customer';
$g2->phone_office = '(617) 443-3000';
$g2->billing_address_city = 'Evendale';
$g2->billing_address_state = 'OH';
$g2->description = 'GE - from legacy ticketing system import.';
$g2->save();
echo "DUP_ACCT:" . $g2->id . ":General Electric Co\n";

// Case under General Electric Co
$cs1 = BeanFactory::newBean('Cases');
$cs1->name = 'Turbine blade inspection data gap';
$cs1->status = 'Open_New';
$cs1->priority = 'P2';
$cs1->type = 'Product';
$cs1->account_id = $g2->id;
$cs1->description = 'Missing 72 hours of turbine inspection data from Evendale facility sensors. Data pipeline interruption during firmware update.';
$cs1->save();
echo "DUP_CASE:" . $cs1->id . ":Turbine blade inspection data gap\n";

// --- Contamination: Johnson Controls International (NOT a duplicate of Johnson & Johnson) ---
$jci = BeanFactory::newBean('Accounts');
$jci->name = 'Johnson Controls International';
$jci->industry = 'Manufacturing';
$jci->account_type = 'Prospect';
$jci->phone_office = '(414) 524-1200';
$jci->website = 'https://www.johnsoncontrols.com';
$jci->billing_address_street = '5757 N Green Bay Avenue';
$jci->billing_address_city = 'Milwaukee';
$jci->billing_address_state = 'WI';
$jci->billing_address_postalcode = '53209';
$jci->billing_address_country = 'USA';
$jci->employees = '100000';
$jci->annual_revenue = '25300000000';
$jci->description = 'Building automation, HVAC systems, and fire & security solutions. Fortune 500 company.';
$jci->save();
echo "CONTAM_ACCT:" . $jci->id . ":Johnson Controls International\n";

// Contact under Johnson Controls
$c4 = BeanFactory::newBean('Contacts');
$c4->first_name = 'Patricia';
$c4->last_name = 'Coleman';
$c4->title = 'VP of Engineering';
$c4->department = 'Building Solutions';
$c4->phone_work = '(414) 524-1250';
$c4->email1 = 'p.coleman@johnsoncontrols.com';
$c4->account_id = $jci->id;
$c4->save();
echo "CONTAM_CONTACT:" . $c4->id . ":Patricia Coleman\n";
?>
PHPEOF

docker cp /tmp/adc_seed.php suitecrm-app:/tmp/adc_seed.php
PHP_OUT=$(docker exec suitecrm-app php /tmp/adc_seed.php 2>&1)
echo "$PHP_OUT"

# Save all injected IDs
echo "$PHP_OUT" | grep '^DUP_ACCT:' | cut -d: -f2 > /tmp/adc_dup_acct_ids.txt
echo "$PHP_OUT" | grep '^DUP_CONTACT:' | cut -d: -f2 > /tmp/adc_dup_contact_ids.txt
echo "$PHP_OUT" | grep '^DUP_OPP:' | cut -d: -f2 > /tmp/adc_dup_opp_ids.txt
echo "$PHP_OUT" | grep '^DUP_CASE:' | cut -d: -f2 > /tmp/adc_dup_case_ids.txt
echo "$PHP_OUT" | grep '^CONTAM_ACCT:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/adc_contam_acct_id.txt
echo "$PHP_OUT" | grep '^CONTAM_CONTACT:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/adc_contam_contact_id.txt
chmod 666 /tmp/adc_*.txt

# 3. Ensure logged in and navigate to Accounts
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

take_screenshot /tmp/adc_initial.png

echo "=== account_dedup_consolidation setup complete ==="
echo "4 duplicate accounts created (2 Boeing, 2 GE) with 3 contacts, 2 opps, 1 case"
echo "1 contamination account (Johnson Controls International) created"
