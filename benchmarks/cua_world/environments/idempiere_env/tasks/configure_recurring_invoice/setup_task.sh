#!/bin/bash
echo "=== Setting up configure_recurring_invoice task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (CRITICAL for verification)
date +%s > /tmp/task_start_time.txt

# 2. Record initial counts to help detect changes
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_INV_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_INV_COUNT" > /tmp/initial_invoice_count.txt

INITIAL_REC_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_recurring WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_REC_COUNT" > /tmp/initial_recurring_count.txt

# 3. Verify C&W Construction exists (Prerequisite)
CW_ID=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE value='C&W' AND ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "")
if [ -z "$CW_ID" ]; then
    echo "WARNING: C&W Construction BP not found. Task might be impossible."
else
    echo "Prerequisite check passed: C&W Construction ID=$CW_ID"
fi

# 4. Ensure Firefox is running and navigate to iDempiere
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="