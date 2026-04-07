#!/bin/bash
echo "=== Setting up configure_inventory_taxes_terms task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing matching taxes to ensure a completely clean state
echo "Cleaning up pre-existing target taxes..."
vtiger_db_query "UPDATE vtiger_inventorytaxinfo SET deleted=1 WHERE taxlabel IN ('GST', 'PST')"
vtiger_db_query "UPDATE vtiger_shippingtaxinfo SET deleted=1 WHERE taxlabel='Shipping GST'"

# 2. Reset Terms and Conditions to a generic default text
echo "Resetting Terms & Conditions..."
vtiger_db_query "UPDATE vtiger_inventory_tandc SET tandc='Standard domestic terms apply. Payment due upon receipt.' WHERE id=1"

# 3. Ensure logged in and navigate to the home page (agent must manually find the settings gear)
echo "Ensuring user is logged in..."
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 3

# 4. Take initial state screenshot
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="