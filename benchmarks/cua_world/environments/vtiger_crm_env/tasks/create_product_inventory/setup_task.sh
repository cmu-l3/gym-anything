#!/bin/bash
echo "=== Setting up create_product_inventory task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Record initial product count
INITIAL_PRODUCT_COUNT=$(vtiger_count "vtiger_products" "1=1")
echo "Initial product count: $INITIAL_PRODUCT_COUNT"
rm -f /tmp/initial_product_count.txt 2>/dev/null || true
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt
chmod 666 /tmp/initial_product_count.txt 2>/dev/null || true

# 2. Verify the target product does not already exist (clean state)
EXISTING=$(vtiger_db_query "SELECT productid FROM vtiger_products WHERE productname='Bamboo Standing Desk Pro' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Product already exists, removing for clean state"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_products WHERE productid=$EXISTING"
    
    # Update count after deletion
    INITIAL_PRODUCT_COUNT=$(vtiger_count "vtiger_products" "1=1")
    echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt
fi

# 3. Ensure Firefox is running, logged into Vtiger, and navigate to Products list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Products&view=List"
sleep 4

# Focus and maximize Firefox to ensure full visibility for the agent
focus_firefox
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Target: Create product 'Bamboo Standing Desk Pro'"
echo "Browser should be on the Products module list view."