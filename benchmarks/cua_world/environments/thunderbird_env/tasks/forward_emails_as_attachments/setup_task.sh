#!/bin/bash
echo "=== Setting up forward_emails_as_attachments task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Ensure Thunderbird is closed before modifying the mailbox
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing running Thunderbird instance..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
    sleep 2
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 1
fi

# Ensure Mail directories exist
mkdir -p "$LOCAL_MAIL_DIR"
touch "${LOCAL_MAIL_DIR}/Inbox"

# Inject the target invoice emails into the Inbox mbox
cat << 'EOF' >> "${LOCAL_MAIL_DIR}/Inbox"

From vendor1@techsupply.com Mon Mar 04 10:00:00 2024
From: vendor1@techsupply.com
To: ga@example.com
Date: Mon, 04 Mar 2024 10:00:00 +0000
Subject: Invoice TS-9921 for Office Monitors
Content-Type: text/plain

Attached is the invoice for the 5 office monitors.
Total: $1250.00
Please remit payment within 30 days.

From billing@cloudhost.com Tue Mar 05 11:30:00 2024
From: billing@cloudhost.com
To: ga@example.com
Date: Tue, 05 Mar 2024 11:30:00 +0000
Subject: Cloud Hosting Invoice - March 2024
Content-Type: text/plain

Your monthly cloud hosting invoice is ready.
Total: $450.00
Services: Compute, Object Storage, Egress.

From events@citycatering.com Wed Mar 06 14:15:00 2024
From: events@citycatering.com
To: ga@example.com
Date: Wed, 06 Mar 2024 14:15:00 +0000
Subject: Catering Invoice - Q1 All-Hands
Content-Type: text/plain

Invoice for the Q1 all-hands catering.
Total: $850.00
Includes: Sandwiches, beverages, delivery fee.
EOF

# Delete the MSF index so Thunderbird rebuilds it immediately upon opening
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf"

# Pre-create Drafts and Sent if they don't exist
touch "${LOCAL_MAIL_DIR}/Drafts"
touch "${LOCAL_MAIL_DIR}/Sent"
chown -R ga:ga "$PROFILE_DIR"

# Launch Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Mozilla Thunderbird"; then
        echo "Thunderbird window found"
        break
    fi
    sleep 1
done

# Wait an additional moment for the UI and indexing to settle
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="