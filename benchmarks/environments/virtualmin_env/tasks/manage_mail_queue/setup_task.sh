#!/bin/bash
echo "=== Setting up manage_mail_queue task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Configure Postfix to hold all mail (simulating a backed-up queue)
# We defer transports so mail stays in the queue and isn't delivered immediately
echo "Configuring Postfix to defer delivery..."
postconf -e "defer_transports = local virtual relay smtp"
systemctl reload postfix
sleep 2

# 2. Clear any existing queue to ensure clean state
postsuper -d ALL
echo "Queue cleared."

# 3. Inject Emails
# We inject 15 spam and 5 legit emails in a mixed order
echo "Injecting emails into queue..."

# Helper to send mail
send_mail() {
    local from="$1"
    local subject="$2"
    local body="$3"
    # usage: send_mail "sender" "subject" "body"
    sendmail -f "$from" -t <<EOF
From: $from
To: root@localhost
Subject: $subject

$body
EOF
}

# Arrays for injection
declare -a ACTIONS
# 5 blocks of (3 spam + 1 legit) = 20 total
for i in {1..5}; do
    ACTIONS+=("spam")
    ACTIONS+=("spam")
    ACTIONS+=("spam")
    ACTIONS+=("legit")
done

SPAM_COUNT=0
LEGIT_COUNT=0

for action in "${ACTIONS[@]}"; do
    if [ "$action" == "spam" ]; then
        SPAM_COUNT=$((SPAM_COUNT+1))
        send_mail "marketing@acmecorp.test" \
                  "EXCLUSIVE OFFER #${SPAM_COUNT}: Buy Now!" \
                  "This is a marketing blast. Please ignore."
    else
        LEGIT_COUNT=$((LEGIT_COUNT+1))
        send_mail "support@acmecorp.test" \
                  "Ticket #${LEGIT_COUNT}992: Password Reset" \
                  "User requested password reset. High priority."
    fi
    # Small sleep to ensure timestamps differ slightly
    sleep 0.2
done

echo "Injected $SPAM_COUNT spam and $LEGIT_COUNT legit emails."

# 4. Verify queue state locally
QUEUE_COUNT=$(mailq | grep -c "^[A-F0-9]")
echo "Current queue size: $QUEUE_COUNT"

# Save initial state for verifier reference
echo "$SPAM_COUNT" > /tmp/initial_spam_count.txt
echo "$LEGIT_COUNT" > /tmp/initial_legit_count.txt

# 5. Ensure Virtualmin/Webmin is ready
ensure_virtualmin_ready

# Navigate specifically to the Postfix Mail Server module index to save agent time
# Module ID is 'postfix'
navigate_to "https://localhost:10000/postfix/index.cgi"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="