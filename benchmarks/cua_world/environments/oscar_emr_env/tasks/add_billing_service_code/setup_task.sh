#!/bin/bash
# Setup script for Add Billing Service Code task

echo "=== Setting up Add Billing Service Code Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure OSCAR is reachable
wait_for_oscar_http 120

# 2. Clean state: Remove the code K083 if it already exists
echo "Ensuring clean state (removing K083 if exists)..."
oscar_query "DELETE FROM billing_service WHERE service_code='K083'" 2>/dev/null || true

# 3. Verify it's gone
COUNT=$(oscar_query "SELECT COUNT(*) FROM billing_service WHERE service_code='K083'")
if [ "$COUNT" != "0" ]; then
    echo "WARNING: Failed to clean up K083 code. Task verification may be affected."
fi

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Ensure Firefox is open on login page
ensure_firefox_on_oscar

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target Code: K083"
echo "Target Fee:  45.00"
echo "Target Desc: Telephone Consultation (Mental Health)"