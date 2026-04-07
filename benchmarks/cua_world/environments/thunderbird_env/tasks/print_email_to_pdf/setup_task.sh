#!/bin/bash
echo "=== Setting up Print Email to PDF Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents folder exists and clear any previous target file
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Peterson_Settlement.pdf
chown ga:ga /home/ga/Documents

# Close Thunderbird if running to safely modify the mbox file
close_thunderbird

# Define target mbox
LOCAL_MAIL_DIR="/home/ga/.thunderbird/default-release/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
INBOX_MSF="${LOCAL_MAIL_DIR}/Inbox.msf"

# Ensure Inbox exists
mkdir -p "$LOCAL_MAIL_DIR"
touch "$INBOX_MBOX"

# Inject the target email if not already there
if ! grep -q "Peterson v. Enron" "$INBOX_MBOX"; then
    echo "Injecting target email into Inbox..."
    
    # Append the email using standard mbox format
    cat >> "$INBOX_MBOX" << 'EOF'

From rpeterson@legal-opposing.com Mon Jan 15 10:00:00 2024
Date: Mon, 15 Jan 2024 10:00:00 -0500
From: Robert Peterson <rpeterson@legal-opposing.com>
To: testuser@example.com
Subject: Final Settlement Terms - Peterson v. Enron
Message-ID: <peterson-enron-12345@legal-opposing.com>
Content-Type: text/plain; charset=UTF-8

Dear Counsel,

Please find below the final agreed-upon terms for the Peterson v. Enron matter.

1. Settlement Amount: $500,000 USD
2. Confidentiality Clause: Both parties agree to strict confidentiality regarding the terms and amount of this settlement.
3. Release of Claims: Plaintiff releases all future claims related to this matter.

Please print this email to PDF and file it in your firm's document management system as the official record.

Regards,
Robert Peterson
Lead Counsel

EOF
    
    # Delete the index to force Thunderbird to rebuild it and discover the new email
    rm -f "$INBOX_MSF"
    chown -R ga:ga /home/ga/.thunderbird
fi

# Start Thunderbird
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize the window for full visibility
sleep 3
maximize_thunderbird

# Take initial screenshot to prove starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="