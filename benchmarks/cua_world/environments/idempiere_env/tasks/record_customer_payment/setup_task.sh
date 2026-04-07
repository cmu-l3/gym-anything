#!/bin/bash
set -e
echo "=== Setting up task: record_customer_payment ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ----------------------------------------------------------------
# 1. Capture Initial Database State
# ----------------------------------------------------------------
CLIENT_ID=$(get_gardenworld_client_id)
echo "GardenWorld Client ID: $CLIENT_ID"

# Record initial payment count to detect new records later
INITIAL_PAYMENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_payment WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_PAYMENT_COUNT" > /tmp/initial_payment_count.txt
echo "Initial payment count: $INITIAL_PAYMENT_COUNT"

# Capture all existing payment IDs to explicitly identify the new one later
# (Saving to a temp file that survives into the task execution)
idempiere_query "SELECT c_payment_id FROM c_payment WHERE ad_client_id=$CLIENT_ID ORDER BY c_payment_id" > /tmp/existing_payment_ids.txt 2>/dev/null || true

# Verify Joe Block exists (sanity check for the environment)
JOE_EXISTS=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE name='Joe Block' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
if [ "$JOE_EXISTS" -eq "0" ]; then
    echo "WARNING: Business Partner 'Joe Block' not found in database!"
else
    echo "Verified Business Partner 'Joe Block' exists."
fi

# ----------------------------------------------------------------
# 2. Prepare Application State
# ----------------------------------------------------------------
echo "--- Ensuring iDempiere is accessible ---"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean slate (handles ZK leave-page dialogs)
ensure_idempiere_open ""

# Focus and maximize the window
FF_WIN=$(DISPLAY=:1 xdotool search --class Firefox 2>/dev/null | head -1)
if [ -n "$FF_WIN" ]; then
    DISPLAY=:1 wmctrl -ia "$FF_WIN" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="