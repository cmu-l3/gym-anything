#!/bin/bash
set -e
echo "=== Setting up Configure Business Details task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
wait_for_manager 60

# ---------------------------------------------------------------------------
# Capture Initial State (Anti-Gaming)
# ---------------------------------------------------------------------------
echo "Recording initial business details state..."
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
rm -f "$COOKIE_FILE"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "http://localhost:8080/login" \
    -d "Username=administrator" \
    -L -o /dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/businesses" -L)
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind', html)
if not m:
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "WARNING: Could not find Northwind business key. Setup might be incomplete."
else
    echo "Business Key: $BIZ_KEY"
    echo "$BIZ_KEY" > /tmp/manager_biz_key.txt

    # Enter business to establish session context
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/start?$BIZ_KEY" -L -o /dev/null

    # Fetch initial settings page
    INITIAL_SETTINGS=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/settings?$BIZ_KEY" -L)
    
    # Try to fetch specific business details form if link exists
    BD_URL=$(echo "$INITIAL_SETTINGS" | grep -o '/business-details-form[^"]*' | head -1)
    if [ -n "$BD_URL" ]; then
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080$BD_URL" -L > /tmp/initial_bd_content.html
    else
        echo "$INITIAL_SETTINGS" > /tmp/initial_bd_content.html
    fi
    
    # Record initial name clearly
    echo "Northwind Traders" > /tmp/initial_biz_name.txt
fi

# ---------------------------------------------------------------------------
# Prepare UI
# ---------------------------------------------------------------------------
# Open Manager.io at the Settings page to start the agent in the right context
echo "Opening Manager.io at Settings page..."
open_manager_at "settings"

# Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="