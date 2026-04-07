#!/bin/bash
echo "=== Setting up create_grouped_quote task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial quote count
INITIAL_QUOTE_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_quotes WHERE deleted=0" | tr -d '[:space:]')
if [ -z "$INITIAL_QUOTE_COUNT" ]; then INITIAL_QUOTE_COUNT=0; fi
echo "$INITIAL_QUOTE_COUNT" > /tmp/initial_quote_count.txt

# Seed realistic account data (Tech Data Corporation) using SuiteCRM PHP API
# This ensures all standard hooks, IDs, and custom table relationships are properly formed
cat > /tmp/seed_techdata.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

$acc = BeanFactory::newBean('Accounts');
$acc->name = 'Tech Data Corporation';
$acc->billing_address_street = '5350 Tech Data Drive';
$acc->billing_address_city = 'Clearwater';
$acc->billing_address_state = 'FL';
$acc->billing_address_postalcode = '33760';
$acc->billing_address_country = 'USA';
$acc->industry = 'Technology';
$acc->account_type = 'Customer';
$acc->save();

echo "Seeded Account ID: " . $acc->id . "\n";
?>
PHPEOF

docker cp /tmp/seed_techdata.php suitecrm-app:/tmp/seed_techdata.php
docker exec suitecrm-app php /tmp/seed_techdata.php

# Ensure SuiteCRM is logged in and ready at the Home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"

# Maximize Firefox for optimal agent visibility
focus_firefox

# Take initial state screenshot
take_screenshot "/tmp/task_initial_state.png"

echo "=== Task setup complete ==="