#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up block_spam_domain task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial blacklist count for comparison
INITIAL_COUNT=$(fs_query "SELECT COUNT(*) FROM blacklists" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_blacklist_count.txt

# Ensure FreeScout is running and we can log in
ensure_logged_in

# 1. Create 'Security' Mailbox
MAILBOX_ID=$(ensure_mailbox_exists "Security" "security@helpdesk.local")
echo "Security Mailbox ID: $MAILBOX_ID"

# 2. Define Phishing Data
MALICIOUS_DOMAIN="network-security-update.io"
SENDER_EMAIL="alert@$MALICIOUS_DOMAIN"
SUBJECT="CRITICAL: Server Access Expiring"
BODY="<p><strong>URGENT SECURITY ALERT</strong></p><p>Your server access credentials for host 192.168.1.55 are expiring in 24 hours.</p><p>Please <a href='http://bad-link.com'>verify your credentials here</a> immediately.</p><p>Failure to renew will result in immediate lockout.</p>"

# 3. Clean up any existing blacklist rules for this domain (Ensure clean state)
echo "Cleaning up old blacklist rules..."
fs_query "DELETE FROM blacklists WHERE value LIKE '%$MALICIOUS_DOMAIN%'" 2>/dev/null || true

# 4. Create the Phishing Conversation
# Check if conversation already exists
EXISTING_CONV=$(find_conversation_by_subject "$SUBJECT")

if [ -z "$EXISTING_CONV" ]; then
    echo "Creating phishing conversation..."
    CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$SENDER_EMAIL" "" "$BODY")
    echo "Created Conversation ID: $CONV_ID"
else
    echo "Phishing conversation already exists."
fi

# 5. Clear Cache to ensure UI updates
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 6. Launch Firefox and navigate to the Security mailbox
# This puts the "trigger" (the ticket) right in front of the agent
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /tmp/firefox.log 2>&1 &"
    sleep 5
else
    navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="