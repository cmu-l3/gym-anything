#!/bin/bash
echo "=== Setting up create_payment_request task ==="

source /workspace/scripts/task_utils.sh
load_btcpay_env

# Record initial payment request count
INITIAL_PR_COUNT=$(get_payment_request_count)
echo "Initial payment request count: ${INITIAL_PR_COUNT}"
echo "${INITIAL_PR_COUNT}" > /tmp/initial_pr_count
date +%s > /tmp/task_start_timestamp

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
echo "Initial PR count: ${INITIAL_PR_COUNT}"
echo "Agent should create a payment request titled 'Invoice #INV-2024-0347 - Custom PCB Assembly' for 425.00 USD"
