#!/bin/bash
echo "=== Setting up grant_system_access task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander to be ready
wait_for_ac_demo

# Ensure we have a clean state for Victor Schulz
ac_login > /dev/null 2>&1

echo "Verifying target user exists..."
VICTOR_IDS=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Victor" and .lastName=="Schulz") | .id' 2>/dev/null)

if [ -z "$VICTOR_IDS" ]; then
    echo "Warning: Victor Schulz not found! Recreating from seed default..."
    ac_api POST "/users" '{"firstName":"Victor","lastName":"Schulz","email":"v.schulz@secureguard.net","company":"SecureGuard Services","enabled":true}' > /dev/null 2>&1
else
    # If multiple exist (dirty state), delete all but the first one
    COUNT=$(echo "$VICTOR_IDS" | wc -w)
    if [ "$COUNT" -gt 1 ]; then
        echo "Found multiple Victor Schulzes. Cleaning up..."
        FIRST="true"
        for uid in $VICTOR_IDS; do
            if [ "$FIRST" = "true" ]; then
                FIRST="false"
            else
                ac_api DELETE "/users/$uid" > /dev/null 2>&1
            fi
        done
    fi
fi

# Launch Firefox and navigate to the Access Commander dashboard
echo "Launching Firefox..."
launch_firefox_to "${AC_URL}/" 8

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured successfully."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="