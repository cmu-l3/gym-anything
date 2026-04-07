#!/bin/bash
set -e
echo "=== Setting up customize_print_format task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempt (remove 'Customer Proposal' format)
echo "--- Cleaning up previous data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
    echo "Warning: Could not get Client ID, defaulting to 11"
fi

# Delete items first (though cascade might handle it, being explicit is safer)
# We find the ID of the format to delete
FORMAT_ID=$(idempiere_query "SELECT AD_PrintFormat_ID FROM AD_PrintFormat WHERE Name='Customer Proposal' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || echo "")

if [ -n "$FORMAT_ID" ] && [ "$FORMAT_ID" != "0" ]; then
    echo "  Deleting existing format ID: $FORMAT_ID"
    idempiere_query "DELETE FROM AD_PrintFormatItem WHERE AD_PrintFormat_ID=$FORMAT_ID" 2>/dev/null || true
    idempiere_query "DELETE FROM AD_PrintFormat WHERE AD_PrintFormat_ID=$FORMAT_ID" 2>/dev/null || true
else
    echo "  No existing format found to clean up."
fi

# 2. Ensure iDempiere/Firefox is running
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean state
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="