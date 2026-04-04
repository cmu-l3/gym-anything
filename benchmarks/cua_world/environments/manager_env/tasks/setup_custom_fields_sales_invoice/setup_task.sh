#!/bin/bash
echo "=== Setting up setup_custom_fields_sales_invoice task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial state of Custom Fields (should be empty/default)
# We need the business key to query the API
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# Login to get session
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null

# Get Business Key for Northwind
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | grep -v "create-new-business" | head -1 | cut -d'?' -f2)

if [ -z "$BIZ_KEY" ]; then
    # Fallback if scraping fails, try specific known patterns or setup data
    # In the setup_manager.sh, Northwind is usually the first/only business
    echo "WARNING: Could not scrape business key, assuming manual navigation."
else
    echo "Business Key found: $BIZ_KEY"
    echo "$BIZ_KEY" > /tmp/biz_key.txt
    
    # Check current custom fields (simple grep check)
    SETTINGS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/custom-fields?$BIZ_KEY" -L)
    echo "$SETTINGS_PAGE" > /tmp/initial_settings_page.html
fi

# Open Manager at Settings to save time
# This uses the helper in task_utils which handles Firefox startup
open_manager_at "settings"

# Maximize and focus happens in open_manager_at, but reinforce it
sleep 15
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="