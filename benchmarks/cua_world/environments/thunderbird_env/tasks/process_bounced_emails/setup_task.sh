#!/bin/bash
set -euo pipefail

echo "=== Setting up Process Bounced Emails Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can safely modify the mbox
close_thunderbird

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_FILE="${LOCAL_MAIL_DIR}/Inbox"

# Ensure the directory exists
mkdir -p "$LOCAL_MAIL_DIR"

# Clean up any existing Bounces folder or text file from previous runs
rm -f "${LOCAL_MAIL_DIR}/Bounces" "${LOCAL_MAIL_DIR}/Bounces.msf"
rm -f "/home/ga/Desktop/bounced_contacts.txt"

# Python script to append realistic bounce emails to the Inbox mbox
cat > /tmp/inject_bounces.py << 'EOF'
import time

mbox_file = "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"

bounces = [
    {
        "subject": "Undelivered Mail Returned to Sender",
        "sender": "MAILER-DAEMON@mail.example.com",
        "date": "Mon, 08 Jan 2024 09:15:00 +0000",
        "body": """This is the mail system at host mail.example.com.

I'm sorry to have to inform you that your message could not
be delivered to one or more recipients. It's attached below.

For further assistance, please send mail to postmaster.

<j.doe@expired-domain.com>: host expired-domain.com[192.0.2.1] said: 550 5.1.1
User unknown (in reply to RCPT TO command)
"""
    },
    {
        "subject": "Delivery Status Notification (Failure)",
        "sender": "postmaster@corp.example.com",
        "date": "Tue, 09 Jan 2024 14:22:10 +0000",
        "body": """Delivery to the following recipient failed permanently:

     former_employee@corp.example.com

Technical details of permanent failure:
The email account that you tried to reach is disabled.
"""
    },
    {
        "subject": "Delivery failure",
        "sender": "postmaster@invalid-domain.net",
        "date": "Wed, 10 Jan 2024 11:05:00 +0000",
        "body": """Message could not be delivered to the following recipient:

sales-info@invalid-domain.net

Recipient address rejected: User unknown in virtual alias table.
"""
    },
    {
        "subject": "Returned mail: see transcript for details",
        "sender": "Mail Delivery Subsystem <MAILER-DAEMON@old-startup.io>",
        "date": "Thu, 11 Jan 2024 16:45:00 +0000",
        "body": """The original message was received at Thu, 11 Jan 2024 16:45:00 +0000
from mail.example.com [198.51.100.5]

   ----- The following addresses had permanent fatal errors -----
<admin@old-startup.io>
    (reason: 550 5.1.1 User unknown)

   ----- Transcript of session follows -----
... while talking to mx.old-startup.io.:
>>> DATA
<<< 550 5.1.1 <admin@old-startup.io>... User unknown
550 5.1.1 <admin@old-startup.io>... User unknown
"""
    }
]

with open(mbox_file, "a") as f:
    for b in bounces:
        # mbox From line
        f.write(f"From {b['sender'].split('<')[-1].strip('>')} {time.ctime()}\n")
        f.write(f"From: {b['sender']}\n")
        f.write(f"To: ga@localhost\n")
        f.write(f"Subject: {b['subject']}\n")
        f.write(f"Date: {b['date']}\n")
        f.write("MIME-Version: 1.0\n")
        f.write("Content-Type: text/plain; charset=utf-8\n\n")
        f.write(b['body'])
        f.write("\n\n")

print("Successfully injected 4 bounce emails into Inbox.")
EOF

python3 /tmp/inject_bounces.py

# Remove the Inbox MSF index so Thunderbird rebuilds it with the new emails
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf"
chown -R ga:ga "${PROFILE_DIR}"

# Start Thunderbird
start_thunderbird

# Wait for window and maximize
wait_for_thunderbird_window 30
sleep 5
maximize_thunderbird

# Click center of desktop to ensure nothing is occluding
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="