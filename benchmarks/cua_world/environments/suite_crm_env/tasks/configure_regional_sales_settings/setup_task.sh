#!/bin/bash
echo "=== Setting up configure_regional_sales_settings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure a clean state by removing any pre-existing records that match our target names
echo "Cleaning up any pre-existing target records..."
suitecrm_db_query "DELETE FROM taxrates WHERE name LIKE '%GST - Canada%' OR name LIKE '%PST - British Columbia%' OR name LIKE '%HST - Ontario%'"
suitecrm_db_query "DELETE FROM shippers WHERE name LIKE '%Canada Post%' OR name LIKE '%Purolator%'"

# 3. Ensure logged in and navigate to the Administration panel
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Administration&action=index"
sleep 4

# 4. Take initial screenshot
take_screenshot /tmp/setup_initial.png

echo "=== configure_regional_sales_settings task setup complete ==="
echo "Task: Create 3 Canadian Tax Rates and 2 Canadian Shipping Providers."