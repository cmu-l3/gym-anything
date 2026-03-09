#!/bin/bash
# Setup for configure_service_catalog task
set -e

echo "=== Setting up Configure Service Catalog task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Record initial DB state (Counts of Categories and Items)
# We try common table names for ServiceDesk Plus (ServiceCategory, ServiceDefinition)
echo "Recording initial counts..."
INIT_CAT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM ServiceCategory" 2>/dev/null || echo "0")
INIT_ITEM_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM ServiceDefinition" 2>/dev/null || echo "0")

# If those tables fail, try generic query or assume 0 (we will rely on specific name matching later anyway)
if [ "$INIT_CAT_COUNT" = "0" ] && [ "$INIT_ITEM_COUNT" = "0" ]; then
    # Fallback to verify if tables exist or use a different query logic if needed
    # For now, we trust the verification will check for *specific* new records
    true
fi

echo "$INIT_CAT_COUNT" > /tmp/initial_category_count.txt
echo "$INIT_ITEM_COUNT" > /tmp/initial_item_count.txt
date +%s > /tmp/task_start_time.txt

echo "Initial Categories: $INIT_CAT_COUNT"
echo "Initial Items: $INIT_ITEM_COUNT"

# 3. Launch Firefox to Login page
# We don't log in automatically because the agent might need to handle login as part of the "Admin" persona flow,
# but usually tasks start logged in. The description says "You need to...".
# Let's provide a logged-in state or at least the login page with credentials provided in description.
# The environment `setup_servicedesk.sh` configures Firefox to open Login.do.
# We will just ensure Firefox is open.

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="