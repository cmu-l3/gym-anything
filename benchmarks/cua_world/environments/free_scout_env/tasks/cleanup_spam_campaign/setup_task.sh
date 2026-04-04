#!/bin/bash
set -e
echo "=== Setting up Cleanup Spam Campaign task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Support Mailbox exists
echo "Ensuring Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

# 2. Seed Legitimate Ticket (The "Trap")
# We create this first so it might be buried if sorted by date, or mixed in
echo "Seeding legitimate ticket..."
create_conversation_via_orm \
    "Q3 Partnership Review - Action Required" \
    "$MAILBOX_ID" \
    "account.manager@legit-lotto.com" \
    "" \
    "Hi Team, attached is the Q3 review document. Please review by Friday."

# 3. Seed Spam Tickets (The Targets)
echo "Seeding spam tickets..."
SPAM_SUBJECTS=(
    "URGENT: You won a prize! Claim now!"
    "FINAL NOTICE: Winnings pending transfer"
    "CONGRATULATIONS! Walmart Gift Card Inside"
    "Re: Your ticket #5599881 is a WINNER"
    "Claim your $1000 reward immediately"
)

for subject in "${SPAM_SUBJECTS[@]}"; do
    create_conversation_via_orm \
        "$subject" \
        "$MAILBOX_ID" \
        "winner@spam-lottery.xyz" \
        "" \
        "Click here to claim your prize! This is not a scam!"
    sleep 1 # Slight delay for realistic timestamps
done

# Clear cache to ensure tickets appear
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 4. Open Firefox to Inbox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    # Launch pointing to the mailbox
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Wait for window
wait_for_window "firefox\|mozilla\|freescout" 30
focus_firefox

# Ensure we are at the mailbox URL
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="