#!/bin/bash
echo "=== Setting up configure_international_currencies task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming detection
date +%s > /tmp/task_start_time.txt

# Delete any existing test currencies to ensure a clean state
echo "Cleaning up existing EUR or GBP currencies..."
suitecrm_db_query "UPDATE currencies SET deleted=1 WHERE iso4217 IN ('EUR', 'GBP')"

# Record initial state of base currency
BASE_RATE=$(suitecrm_db_query "SELECT conversion_rate FROM currencies WHERE id='-99' AND deleted=0")
echo "$BASE_RATE" > /tmp/initial_base_rate.txt

# Ensure logged in and navigate to Home dashboard
echo "Ensuring user is logged in..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# Take initial screenshot
take_screenshot /tmp/configure_currencies_initial.png

echo "=== configure_international_currencies task setup complete ==="