#!/bin/bash
set -e
echo "=== Setting up create_bank_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up any pre-existing test data to ensure clean state
echo "--- Cleaning up pre-existing 'Chase Bank NA' records ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Deactivate any existing bank with this name to avoid unique constraint errors or confusion
    idempiere_query "UPDATE C_Bank SET IsActive='N', Name=Name||'_OLD_'||to_char(now(),'HH24MISS') WHERE Name='Chase Bank NA' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true
fi

# 2. Record initial counts for verification baseline
INITIAL_BANK_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_Bank WHERE AD_Client_ID=${CLIENT_ID:-11} AND IsActive='Y'" 2>/dev/null || echo "0")
INITIAL_ACCT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_BankAccount WHERE AD_Client_ID=${CLIENT_ID:-11} AND IsActive='Y'" 2>/dev/null || echo "0")

echo "Initial Bank count: $INITIAL_BANK_COUNT"
echo "Initial Bank Account count: $INITIAL_ACCT_COUNT"

# Save to temp files
echo "$INITIAL_BANK_COUNT" > /tmp/initial_bank_count.txt
echo "$INITIAL_ACCT_COUNT" > /tmp/initial_acct_count.txt
chmod 666 /tmp/initial_bank_count.txt /tmp/initial_acct_count.txt 2>/dev/null || true

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere dashboard ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
navigate_to_dashboard

# Maximize window for better agent visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="