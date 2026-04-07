#!/bin/bash
echo "=== Setting up create_pos_app task ==="

source /workspace/scripts/task_utils.sh
load_btcpay_env

# Record initial app count
INITIAL_APP_COUNT=$(get_apps_count)
echo "Initial app count: ${INITIAL_APP_COUNT}"
echo "${INITIAL_APP_COUNT}" > /tmp/initial_app_count
date +%s > /tmp/task_start_timestamp

# Delete any existing POS app named "Satoshi's Coffee House" to ensure clean state
APPS_RESPONSE=$(btcpay_api GET "/api/v1/stores/${STORE_ID}/apps")
EXISTING_APP_ID=$(echo "$APPS_RESPONSE" | jq -r '.[] | select(.appName == "Satoshi'\''s Coffee House") | .id // empty' 2>/dev/null)
if [ -n "$EXISTING_APP_ID" ]; then
    echo "Removing existing POS app: ${EXISTING_APP_ID}"
    btcpay_api DELETE "/api/v1/stores/${STORE_ID}/apps/${EXISTING_APP_ID}" > /dev/null 2>&1
    INITIAL_APP_COUNT=$((INITIAL_APP_COUNT - 1))
    echo "${INITIAL_APP_COUNT}" > /tmp/initial_app_count
fi

# Ensure BTCPay Server is accessible
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BTCPAY_URL}" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "WARNING: BTCPay Server not responding (HTTP $HTTP_CODE)"
fi

# Ensure Firefox is running
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    echo "Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_btcpay.log 2>&1 &"
    sleep 5
    wait_for_firefox 30
fi

# Focus and maximize Firefox
focus_firefox
sleep 1

# Only login if we're on the login page (post_start login may have already succeeded)
CURRENT_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if echo "$CURRENT_TITLE" | grep -qi "sign in\|login"; then
    echo "On login page, logging in..."
    btcpay_firefox_login
else
    echo "Already logged in (title: $CURRENT_TITLE)"
fi

# Navigate to store dashboard
navigate_to "http://localhost/"
sleep 3

focus_firefox
sleep 1

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="
echo "Initial app count: ${INITIAL_APP_COUNT}"
echo "Agent should create a POS app named 'Satoshi Coffee House' with 6 coffee products"
