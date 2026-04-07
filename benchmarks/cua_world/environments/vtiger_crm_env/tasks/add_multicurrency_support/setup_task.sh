#!/bin/bash
echo "=== Setting up add_multicurrency_support task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any existing EUR or GBP currencies to ensure agent must create them
echo "Cleaning up any pre-existing EUR or GBP currencies..."
vtiger_db_query "DELETE FROM vtiger_currency_info WHERE currency_code IN ('EUR', 'GBP')"

# 2. Record initial currency count
INITIAL_CURRENCY_COUNT=$(vtiger_count "vtiger_currency_info" "deleted=0")
echo "Initial currency count: $INITIAL_CURRENCY_COUNT"

# 3. Record max currency ID to detect newly created records (Anti-gaming)
MAX_CURRENCY_ID=$(vtiger_db_query "SELECT MAX(id) FROM vtiger_currency_info" | tr -d '[:space:]')
if [ -z "$MAX_CURRENCY_ID" ] || [ "$MAX_CURRENCY_ID" == "NULL" ]; then
    MAX_CURRENCY_ID=0
fi
echo "Max initial currency ID: $MAX_CURRENCY_ID"

# Save initial state variables
cat > /tmp/initial_currency_state.json << EOF
{
  "initial_count": ${INITIAL_CURRENCY_COUNT:-0},
  "max_initial_id": ${MAX_CURRENCY_ID:-0}
}
EOF
chmod 666 /tmp/initial_currency_state.json 2>/dev/null || true

# 4. Ensure logged in and navigate to Vtiger CRM Settings Dashboard
# The Settings index is a good starting point for admin tasks
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Vtiger&parent=Settings&view=Index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/add_multicurrency_initial.png

echo "=== add_multicurrency_support task setup complete ==="
echo "Task: Add Euro (0.92) and GBP (0.79) as active currencies."
echo "Agent should navigate to Currencies in CRM Settings and add them."