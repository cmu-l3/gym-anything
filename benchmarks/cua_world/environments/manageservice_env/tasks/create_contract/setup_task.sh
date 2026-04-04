#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_contract task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for SDP to be installed and running
ensure_sdp_running

# Record initial contract count
# We use the utility function to execute SQL against the SDP database
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM contractinfo;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_contract_count.txt
echo "Initial contract count: $INITIAL_COUNT"

# Ensure the vendor "Cisco Systems" exists
# This is crucial so the agent doesn't get stuck creating a vendor
VENDOR_EXISTS=$(sdp_db_exec "SELECT COUNT(*) FROM vendordetails WHERE LOWER(vendorname) LIKE '%cisco%';" 2>/dev/null || echo "0")

if [ "$VENDOR_EXISTS" = "0" ] || [ -z "$VENDOR_EXISTS" ]; then
    echo "Creating Cisco Systems vendor via Database Insertion..."
    # Direct DB insertion is faster and more reliable for setup than API in this environment
    # Note: ciid usually auto-increments or is handled by triggers in SDP
    sdp_db_exec "INSERT INTO vendordetails (vendorname, description, contactperson, email, phone) VALUES ('Cisco Systems', 'Cisco Systems Inc - Network Equipment Vendor', 'Enterprise Support', 'support@cisco.com', '1-800-553-2447');" 2>/dev/null || true
    echo "Vendor inserted."
else
    echo "Vendor 'Cisco Systems' already exists."
fi

# Launch Firefox on SDP login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Allow time for window to appear
sleep 5

# Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="