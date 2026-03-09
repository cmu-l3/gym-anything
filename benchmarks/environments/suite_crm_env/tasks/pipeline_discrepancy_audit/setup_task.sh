#!/bin/bash
set -e
echo "=== Setting up pipeline_discrepancy_audit task ==="

source /workspace/scripts/task_utils.sh

# 0. Record timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Record baseline opportunity state
echo "--- Recording baseline ---"
suitecrm_db_query "SELECT id, name, amount, sales_stage, deleted FROM opportunities ORDER BY name" > /tmp/pda_baseline_opps.txt
chmod 666 /tmp/pda_baseline_opps.txt

# Save original amounts for the two records we will inflate
ATT_OPP_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='AT&T - Customer Experience Analytics' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
TESLA_OPP_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='Tesla - Manufacturing Execution System' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
echo "$ATT_OPP_ID" > /tmp/pda_att_opp_id.txt
echo "$TESLA_OPP_ID" > /tmp/pda_tesla_opp_id.txt
chmod 666 /tmp/pda_att_opp_id.txt /tmp/pda_tesla_opp_id.txt

# 2. Create duplicate opportunities and one contamination opportunity via PHP
cat > /tmp/pda_seed.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html');
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

$jpmorgan_id = $db->getOne("SELECT id FROM accounts WHERE name='JPMorgan Chase & Co.' AND deleted=0");
$nvidia_id   = $db->getOne("SELECT id FROM accounts WHERE name='NVIDIA Corporation' AND deleted=0");
$tesla_id    = $db->getOne("SELECT id FROM accounts WHERE name='Tesla Inc.' AND deleted=0");
$att_id      = $db->getOne("SELECT id FROM accounts WHERE name='AT&T Inc.' AND deleted=0");
$deloitte_id = $db->getOne("SELECT id FROM accounts WHERE name='Deloitte LLP' AND deleted=0");

// 4 duplicate opportunities (mimic real deals already in the system)
$dupes = [
    ['name' => 'JPMorgan Chase - AI Fraud Detection System',    'amount' => '5500000',  'sales_stage' => 'Negotiation/Review',   'probability' => '80', 'date_closed' => '2026-04-30', 'account_id' => $jpmorgan_id, 'lead_source' => 'Conference',    'description' => 'ML-based fraud detection for consumer banking division. Migrated from legacy pipeline tracker.'],
    ['name' => 'NVIDIA - DGX Cluster Orchestration Suite',      'amount' => '750000',   'sales_stage' => 'Proposal/Price Quote', 'probability' => '65', 'date_closed' => '2026-06-30', 'account_id' => $nvidia_id,   'lead_source' => 'Trade Show',    'description' => 'Cluster orchestration for DGX SuperPOD infrastructure. Re-entered from Q4 import.'],
    ['name' => 'Tesla Gigafactory - MES Platform',              'amount' => '3800000',  'sales_stage' => 'Needs Analysis',       'probability' => '25', 'date_closed' => '2026-09-30', 'account_id' => $tesla_id,    'lead_source' => 'Web Site',      'description' => 'Manufacturing execution system for Gigafactory production. Possible re-entry from partner channel.'],
    ['name' => 'AT&T Wireless - CX Analytics Suite',            'amount' => '2100000',  'sales_stage' => 'Value Proposition',    'probability' => '30', 'date_closed' => '2026-08-15', 'account_id' => $att_id,      'lead_source' => 'Existing Customer', 'description' => 'Customer journey analytics for wireless subscriber base. Imported from regional pipeline.'],
];

$ids = [];
foreach ($dupes as $d) {
    $bean = BeanFactory::newBean('Opportunities');
    foreach ($d as $k => $v) { $bean->$k = $v; }
    $bean->save();
    $ids[] = $bean->id;
    echo "DUPE:" . $bean->id . "\n";
}

// 1 contamination (legitimate new opportunity - NOT a duplicate)
$bean = BeanFactory::newBean('Opportunities');
$bean->name         = 'Deloitte - Digital Transformation Advisory';
$bean->amount       = '950000';
$bean->sales_stage  = 'Proposal/Price Quote';
$bean->probability  = '65';
$bean->date_closed  = '2026-07-15';
$bean->account_id   = $deloitte_id;
$bean->lead_source  = 'Partner';
$bean->description  = 'Strategic advisory engagement covering AI adoption, cloud migration, and process automation for three business units.';
$bean->save();
echo "LEGIT:" . $bean->id . "\n";
?>
PHPEOF

docker cp /tmp/pda_seed.php suitecrm-app:/tmp/pda_seed.php
PHP_OUT=$(docker exec suitecrm-app php /tmp/pda_seed.php 2>&1)
echo "$PHP_OUT"

# Save injected IDs
echo "$PHP_OUT" | grep '^DUPE:' | cut -d: -f2 > /tmp/pda_dupe_ids.txt
echo "$PHP_OUT" | grep '^LEGIT:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/pda_legit_id.txt
chmod 666 /tmp/pda_dupe_ids.txt /tmp/pda_legit_id.txt

# 3. Inflate two existing opportunity amounts
suitecrm_db_query "UPDATE opportunities SET amount=4200000.00 WHERE id='${ATT_OPP_ID}' AND deleted=0"
suitecrm_db_query "UPDATE opportunities SET amount=5700000.00 WHERE id='${TESLA_OPP_ID}' AND deleted=0"
echo "Inflated AT&T from 2100000 to 4200000"
echo "Inflated Tesla from 3800000 to 5700000"

# 4. Record all original (non-duplicate) opportunity IDs for gate check
suitecrm_db_query "SELECT id FROM opportunities WHERE deleted=0" > /tmp/pda_all_opp_ids.txt
chmod 666 /tmp/pda_all_opp_ids.txt

# 5. Ensure logged in and navigate to Opportunities
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Opportunities&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/pda_initial.png

echo "=== pipeline_discrepancy_audit setup complete ==="
echo "4 duplicate opportunities injected, 2 amounts inflated, 1 contamination added"
