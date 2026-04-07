#!/bin/bash
set -e
echo "=== Setting up create_mail_template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing template with this name to ensure a fresh start
echo "--- Cleaning up previous test data ---"
CLIENT_ID=$(get_gardenworld_client_id)
# Default to 11 if query fails
CLIENT_ID=${CLIENT_ID:-11}

# Delete existing record if present (using name as key)
idempiere_query "DELETE FROM R_MailText WHERE Name='Vendor Order Inquiry' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true
echo "  Cleanup complete."

# 2. Ensure Firefox is running and ready
echo "--- Checking application state ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Ensure iDempiere is open and focused
ensure_idempiere_open ""

# Maximize window for better visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot captured."

echo "=== Task setup complete ==="