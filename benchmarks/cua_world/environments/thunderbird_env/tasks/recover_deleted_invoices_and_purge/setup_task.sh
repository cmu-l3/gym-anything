#!/bin/bash
echo "=== Setting up Recover Deleted Invoices Task ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Ensure Thunderbird is NOT running while manipulating its storage files
echo "Ensuring Thunderbird is closed before file manipulation..."
pkill -f "thunderbird" 2>/dev/null || true
sleep 3

# Ensure mail directory exists
mkdir -p "$LOCAL_MAIL_DIR"

TRASH_FILE="${LOCAL_MAIL_DIR}/Trash"
INBOX_FILE="${LOCAL_MAIL_DIR}/Inbox"

# Remove existing Trash and MSF indices to force Thunderbird to rebuild them
rm -f "$TRASH_FILE" "${LOCAL_MAIL_DIR}/Trash.msf" 2>/dev/null
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf" 2>/dev/null
touch "$TRASH_FILE"

echo "Populating Trash with decoy emails and target invoices..."

# Helper to generate a dummy email in mbox format
# X-Mozilla-Status: 0001 means READ
generate_email() {
    local subject="$1"
    local sender="$2"
    local date_str="$(date -R)"
    
    cat <<EOF >> "$TRASH_FILE"
From - $(date)
X-Mozilla-Status: 0001
X-Mozilla-Status2: 00000000
From: $sender
To: ga@localhost
Subject: $subject
Date: $date_str
Content-Type: text/plain; charset=UTF-8

This is the body of the email: $subject.
Please process accordingly.
EOF
    echo "" >> "$TRASH_FILE"
}

# 1. Add Decoy emails
generate_email "Discount Pharmacy Offer" "spam@junkmail.com"
generate_email "Meeting notes from Tuesday" "colleague@company.com"
generate_email "Fwd: Funny cat video" "friend@personal.net"
generate_email "Your subscription receipt" "billing@streaming.com"
generate_email "Action Required: Update your password" "security@it-dept.com"

# Add more generic decoys to ensure the folder is cluttered (~15 more)
for i in {1..15}; do
    generate_email "Newsletter Digest #$i" "newsletter@updates.com"
done

# 2. Add Target Invoices
generate_email "Apex Corp - Q3 Invoice #1048" "billing@apexcorp.com"
generate_email "Apex Corp - Q3 Invoice #1049" "billing@apexcorp.com"
generate_email "Overdue: Apex Corp Invoice #1022" "collections@apexcorp.com"

chown -R ga:ga /home/ga/.thunderbird

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release > /tmp/thunderbird.log 2>&1 &"

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

# Maximize and focus Thunderbird
sleep 3
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="