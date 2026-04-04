#!/bin/bash
set -e
echo "=== Setting up stale_pipeline_cleanup task ==="

source /workspace/scripts/task_utils.sh

# 0. Record timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Record baseline
echo "--- Recording baseline ---"
suitecrm_db_query "SELECT id, name, amount, sales_stage, probability, date_closed FROM opportunities WHERE deleted=0 ORDER BY name" > /tmp/spc_baseline.txt
chmod 666 /tmp/spc_baseline.txt

# 2. Modify existing opportunities to introduce inconsistencies

# 2a. Stale deals: active stage but close date far in the past (>60 days)
EXXON_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='ExxonMobil - IoT Sensor Analytics' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
JNJ_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='Johnson & Johnson - Clinical Trial Mgmt' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
suitecrm_db_query "UPDATE opportunities SET date_closed='2025-06-15' WHERE id='${EXXON_ID}'"
suitecrm_db_query "UPDATE opportunities SET date_closed='2025-09-01' WHERE id='${JNJ_ID}'"
echo "Made ExxonMobil stale (date_closed=2025-06-15, stage=Prospecting)"
echo "Made J&J stale (date_closed=2025-09-01, stage=Id. Decision Makers)"

# 2b. Probability mismatches: probability doesn't match stage
NVIDIA_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='NVIDIA - GPU Cluster Management Platform' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
ATT_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='AT&T - Customer Experience Analytics' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
GS_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='Goldman Sachs - Compliance Dashboard' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
suitecrm_db_query "UPDATE opportunities SET probability=10 WHERE id='${NVIDIA_ID}'"
suitecrm_db_query "UPDATE opportunities SET probability=95 WHERE id='${ATT_ID}'"
suitecrm_db_query "UPDATE opportunities SET probability=25 WHERE id='${GS_ID}'"
echo "Set NVIDIA prob=10 (stage=Proposal/Price Quote, should be 65)"
echo "Set AT&T prob=95 (stage=Value Proposition, should be 30)"
echo "Set Goldman prob=25 (stage=Negotiation/Review, should be 80)"

# 2c. Create a Closed Won deal with future close date
cat > /tmp/spc_seed.php << 'PHPEOF'
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
chdir('/var/www/html');
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

$apple_id = $db->getOne("SELECT id FROM accounts WHERE name='Apple Inc.' AND deleted=0");
$ge_id    = $db->getOne("SELECT id FROM accounts WHERE name='General Electric Company' AND deleted=0");

// Closed Won with future close date
$bean = BeanFactory::newBean('Opportunities');
$bean->name        = 'Apple - ML Infrastructure Renewal';
$bean->amount      = '1800000';
$bean->sales_stage = 'Closed Won';
$bean->probability = '100';
$bean->date_closed = '2027-06-15';
$bean->account_id  = $apple_id;
$bean->lead_source = 'Existing Customer';
$bean->description = 'Annual ML infrastructure license renewal. Three-year commitment for on-premise GPU cluster management.';
$bean->save();
echo "FUTURE_WON:" . $bean->id . "\n";

// Active stage with 100% probability (wrong)
$bean2 = BeanFactory::newBean('Opportunities');
$bean2->name        = 'GE Aviation - Predictive Analytics v2';
$bean2->amount      = '1400000';
$bean2->sales_stage = 'Needs Analysis';
$bean2->probability = '100';
$bean2->date_closed = '2026-08-30';
$bean2->account_id  = $ge_id;
$bean2->lead_source = 'Trade Show';
$bean2->description = 'Phase 2 predictive analytics for jet engine fleet. Vibration pattern analysis and remaining useful life prediction.';
$bean2->save();
echo "WRONG_PROB:" . $bean2->id . "\n";
?>
PHPEOF

docker cp /tmp/spc_seed.php suitecrm-app:/tmp/spc_seed.php
PHP_OUT=$(docker exec suitecrm-app php /tmp/spc_seed.php 2>&1)
echo "$PHP_OUT"

# Save IDs
echo "$PHP_OUT" | grep '^FUTURE_WON:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/spc_future_won_id.txt
echo "$PHP_OUT" | grep '^WRONG_PROB:' | cut -d: -f2 | tr -d '[:space:]' > /tmp/spc_wrong_prob_id.txt
echo "$EXXON_ID" > /tmp/spc_exxon_id.txt
echo "$JNJ_ID" > /tmp/spc_jnj_id.txt
echo "$NVIDIA_ID" > /tmp/spc_nvidia_id.txt
echo "$ATT_ID" > /tmp/spc_att_id.txt
echo "$GS_ID" > /tmp/spc_gs_id.txt
chmod 666 /tmp/spc_*.txt

# 3. Ensure logged in and navigate to Opportunities
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Opportunities&action=index"
sleep 3

take_screenshot /tmp/spc_initial.png

echo "=== stale_pipeline_cleanup setup complete ==="
echo "2 stale deals, 3 probability mismatches, 1 future Closed Won, 1 wrong-probability active"
