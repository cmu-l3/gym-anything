#!/bin/bash
set -e
echo "=== Setting up create_account_plan task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure clean state: Delete "Business Pro" plan if it exists
if virtualmin list-plans --name-only 2>/dev/null | grep -q "^Business Pro$"; then
    echo "Cleaning up existing 'Business Pro' plan..."
    virtualmin delete-plan --name "Business Pro" 2>/dev/null || true
fi

# 2. Ensure target domain exists and is on Default Plan
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating missing domain acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --plan "Default Plan" --features "web dns mail mysql" 2>/dev/null
else
    # Reset to Default Plan if needed
    CURRENT_PLAN=$(virtualmin list-domains --domain acmecorp.test --multiline | grep "Plan:" | sed 's/.*: //')
    if [ "$CURRENT_PLAN" != "Default Plan" ]; then
        echo "Resetting acmecorp.test to Default Plan..."
        virtualmin modify-domain --domain acmecorp.test --plan "Default Plan" 2>/dev/null || true
    fi
fi

# 3. Record initial state of plans (for anti-gaming verification)
virtualmin list-plans --name-only > /tmp/initial_plans_list.txt 2>/dev/null || true

# 4. Prepare GUI
ensure_virtualmin_ready

# Navigate to Account Plans page to help the agent start
# Virtualmin URL structure for plans list
navigate_to "https://localhost:10000/virtual-server/list_plans.cgi"
sleep 4

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="