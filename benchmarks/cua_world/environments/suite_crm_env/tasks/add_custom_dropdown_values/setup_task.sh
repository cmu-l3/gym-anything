#!/bin/bash
echo "=== Setting up add_custom_dropdown_values task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Record initial account count
INITIAL_ACCOUNT_COUNT=$(get_account_count)
echo "Initial account count: $INITIAL_ACCOUNT_COUNT"
rm -f /tmp/initial_account_count.txt 2>/dev/null || true
echo "$INITIAL_ACCOUNT_COUNT" > /tmp/initial_account_count.txt
chmod 666 /tmp/initial_account_count.txt 2>/dev/null || true

# 2. Verify the target account does not already exist
if account_exists "SolarTech Solutions"; then
    echo "WARNING: Account SolarTech Solutions already exists, removing..."
    soft_delete_record "accounts" "name='SolarTech Solutions'"
fi

# 3. Check if dropdown values already exist in the custom language files (baseline)
HAS_INITIAL_RENEWABLE=$(docker exec suitecrm-app grep -qri "Renewable_Energy" /var/www/html/custom/ 2>/dev/null && echo "true" || echo "false")
HAS_INITIAL_WEBINAR=$(docker exec suitecrm-app grep -qri "Webinar" /var/www/html/custom/ 2>/dev/null && echo "true" || echo "false")
echo "Initial custom dropdown state: Renewable=$HAS_INITIAL_RENEWABLE, Webinar=$HAS_INITIAL_WEBINAR"
echo "$HAS_INITIAL_RENEWABLE" > /tmp/has_initial_renewable.txt
echo "$HAS_INITIAL_WEBINAR" > /tmp/has_initial_webinar.txt

# 4. Ensure logged in and navigate to the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/add_custom_dropdown_values_initial.png

echo "=== add_custom_dropdown_values task setup complete ==="