#!/bin/bash
echo "=== Setting up create_opportunity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial opportunity count
INITIAL_OPP_COUNT=$(get_opp_count)
echo "Initial opportunity count: $INITIAL_OPP_COUNT"
rm -f /tmp/initial_opp_count.txt 2>/dev/null || true
echo "$INITIAL_OPP_COUNT" > /tmp/initial_opp_count.txt
chmod 666 /tmp/initial_opp_count.txt 2>/dev/null || true

# 2. Verify the target opportunity does not already exist
if opp_exists "GE Aerospace - Predictive Maintenance Platform"; then
    echo "WARNING: Opportunity already exists, removing"
    soft_delete_record "opportunities" "name='GE Aerospace - Predictive Maintenance Platform'"
fi

# 3. Ensure logged in and navigate to Opportunities list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Opportunities&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_opportunity_initial.png

echo "=== create_opportunity task setup complete ==="
echo "Task: Create a new opportunity for GE Aerospace"
echo "Agent should click Create Opportunity and fill in the form"
