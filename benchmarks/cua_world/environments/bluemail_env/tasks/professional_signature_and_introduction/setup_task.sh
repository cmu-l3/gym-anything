#!/bin/bash
set -e
echo "=== Setting up professional_signature_and_introduction task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Reset Mail Environment
# ============================================================
# Ensure Dovecot/Postfix are running
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
systemctl restart postfix 2>/dev/null || true
sleep 2

# Clean Drafts and Sent folders to ensure we catch new work
rm -f /home/ga/Maildir/.Drafts/cur/* /home/ga/Maildir/.Drafts/new/* 2>/dev/null || true
rm -f /home/ga/Maildir/.Sent/cur/* /home/ga/Maildir/.Sent/new/* 2>/dev/null || true

# Populate Inbox with some context (Ham emails)
# This makes the environment look realistic
if [ -d "/workspace/assets/emails/ham" ]; then
    echo "Populating inbox with context..."
    cp /workspace/assets/emails/ham/ham_00[1-9].eml /home/ga/Maildir/cur/ 2>/dev/null || true
    chown ga:ga /home/ga/Maildir/cur/* 2>/dev/null || true
fi

# ============================================================
# 2. Reset BlueMail Configuration (Clear previous signatures)
# ============================================================
# We want to ensure the agent actually sets the signature, not just finds an old one.
# However, we must preserve the account login (stored in ~/.config/BlueMail usually).
# Signature is often in preferences. We will try to sed/remove specific signature keys if possible,
# or just rely on the verifier checking the timestamp of the config change/email.
# Since exact config path varies by version, we rely on the agent overwriting or creating it.

# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
sleep 2
maximize_bluemail

# ============================================================
# 3. Record Initial State
# ============================================================
# Count initial drafts/sent (should be 0 after clean)
ls -1 /home/ga/Maildir/.Drafts/cur/ 2>/dev/null | wc -l > /tmp/initial_draft_count.txt
ls -1 /home/ga/Maildir/.Sent/cur/ 2>/dev/null | wc -l > /tmp/initial_sent_count.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="