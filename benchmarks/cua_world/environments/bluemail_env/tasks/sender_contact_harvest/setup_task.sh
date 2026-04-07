#!/bin/bash
echo "=== Setting up sender_contact_harvest task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/contact_list.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 2. Ensure BlueMail is running
# We need the app running so the agent can inspect emails via GUI if they choose
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

# Wait for window and maximize
wait_for_bluemail_window 60
maximize_bluemail

# 3. Record initial inbox state (for integrity check)
# Count files in inbox to ensure agent doesn't delete them
INBOX_COUNT=$(ls -1 /home/ga/Maildir/cur/ /home/ga/Maildir/new/ 2>/dev/null | grep -v '^\.' | wc -l)
echo "$INBOX_COUNT" > /tmp/initial_inbox_count.txt

# 4. Generate Ground Truth (Hidden from agent)
# We extract all From addresses from the actual Maildir files to know what's possible
echo "Generating ground truth data..."
grep -rPh "^From:" /home/ga/Maildir/cur/ /home/ga/Maildir/new/ 2>/dev/null | \
    grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    tr '[:upper:]' '[:lower:]' | \
    sort -u > /tmp/ground_truth_senders.txt

GT_COUNT=$(cat /tmp/ground_truth_senders.txt | wc -l)
echo "Ground truth contains $GT_COUNT unique senders."

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="