#!/bin/bash
echo "=== Setting up Warranty Auto-Reply Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define paths
TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${TB_PROFILE}/Mail/Local Folders"

# Ensure Thunderbird profile structure exists
su - ga -c "mkdir -p '${LOCAL_MAIL_DIR}'"

# Clear any existing Templates or filters to ensure a clean state
su - ga -c "rm -f '${LOCAL_MAIL_DIR}/Templates'"
su - ga -c "rm -f '${LOCAL_MAIL_DIR}/Templates.msf'"
su - ga -c "rm -f '${LOCAL_MAIL_DIR}/msgFilterRules.dat'"
su - ga -c "touch '${LOCAL_MAIL_DIR}/Templates'"

# Inject realistic "Warranty Claim" emails into the Inbox
INBOX_FILE="${LOCAL_MAIL_DIR}/Inbox"
su - ga -c "cat << 'EOF' >> '${INBOX_FILE}'

From customer_a@example.com Mon Mar 09 09:15:00 2026
Date: Mon, 09 Mar 2026 09:15:00 -0500
From: Alice Smith <customer_a@example.com>
To: support@company.com
Subject: Warranty Claim - Broken Handle

Hello, the handle on my recent purchase broke after two weeks. I would like to file a claim.
EOF"

su - ga -c "cat << 'EOF' >> '${INBOX_FILE}'

From customer_b@example.com Mon Mar 09 10:30:00 2026
Date: Mon, 09 Mar 2026 10:30:00 -0500
From: Bob Jones <customer_b@example.com>
To: support@company.com
Subject: Urgent Warranty Claim

The device won't turn on anymore. Please help me with a replacement.
EOF"

# Start Thunderbird if not running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile '${TB_PROFILE}' &"
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Allow UI to stabilize
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="