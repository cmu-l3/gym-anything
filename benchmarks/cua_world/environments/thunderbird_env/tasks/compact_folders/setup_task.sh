#!/bin/bash
set -e
echo "=== Setting up compact_folders task ==="

# Record task start time for anti-gaming (mtime checks)
date +%s > /tmp/task_start_time.txt

# Use shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Paths
PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
JUNK_MBOX="${LOCAL_MAIL_DIR}/Junk"

# Ensure Thunderbird is closed before modifying mbox files directly
if pgrep -f "thunderbird" > /dev/null; then
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 3
fi

# 1. Count current active (non-deleted) emails before injecting bloat
INBOX_ACTIVE_COUNT=$(grep -c "^From " "$INBOX_MBOX" 2>/dev/null || echo "0")
JUNK_ACTIVE_COUNT=$(grep -c "^From " "$JUNK_MBOX" 2>/dev/null || echo "0")

echo "Active emails before bloat: Inbox=$INBOX_ACTIVE_COUNT, Junk=$JUNK_ACTIVE_COUNT"

# 2. Inject "deleted" ghost messages into Inbox to simulate bloat
# We use realistic headers and payload to mimic real emails taking up space.
# X-Mozilla-Status: 0009 marks it as deleted in Thunderbird's UI.
echo "Injecting deleted messages into Inbox..."
for i in $(seq 1 25); do
    cat >> "$INBOX_MBOX" << DELETED_MSG
From ghost-deleted-${i}@example.com Mon Jan 15 10:${i}:00 2024
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00800000
Message-ID: <deleted-inbox-${i}@ghost.local>
Date: Mon, 15 Jan 2024 10:${i}:00 -0500
From: Deleted Notification System <notifications-${i}@automated-alerts.example.com>
To: testuser@example.com
Subject: [AUTO] Daily Report #${i} - System Status Update
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

This is an automated system notification that was previously deleted by the user.
It contains routine operational data that is no longer needed and is taking up
disk space in the mail folder. It should be removed during folder compaction.

$(python3 -c "import string,random; print(''.join(random.choices(string.ascii_letters+' \n', k=15000)))" 2>/dev/null || head -c 15000 /dev/urandom | base64)

DELETED_MSG
done

# 3. Inject "deleted" ghost messages into Junk
echo "Injecting deleted messages into Junk..."
for i in $(seq 1 15); do
    cat >> "$JUNK_MBOX" << DELETED_SPAM
From ghost-spam-${i}@spambot.example.com Tue Feb 20 08:${i}:00 2024
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00800000
Message-ID: <deleted-junk-${i}@ghost.local>
Date: Tue, 20 Feb 2024 08:${i}:00 -0500
From: Special Offer ${i} <deals-${i}@discount-warehouse.example.com>
To: testuser@example.com
Subject: URGENT: Claim Your Prize #${i} - Limited Time Offer!!!
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

This is a previously deleted spam message that is bloating the Junk folder.
It should be removed during compaction.
$(python3 -c "import string,random; print(''.join(random.choices(string.ascii_letters+' \n', k=12000)))" 2>/dev/null || head -c 12000 /dev/urandom | base64)

DELETED_SPAM
done

# 4. Delete .msf index files so Thunderbird is forced to rebuild them from the bloated mbox
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Junk.msf" 2>/dev/null || true

# Fix ownership
chown -R ga:ga "$PROFILE_DIR"

# 5. Record initial file sizes AFTER bloat injection
INBOX_SIZE=$(stat -c%s "$INBOX_MBOX" 2>/dev/null || echo "0")
JUNK_SIZE=$(stat -c%s "$JUNK_MBOX" 2>/dev/null || echo "0")

echo "Initial sizes after bloat: Inbox=${INBOX_SIZE} bytes, Junk=${JUNK_SIZE} bytes"

# 6. Save initial state for the verifier to use later
cat > /tmp/initial_sizes.json << EOF
{
    "inbox_active_count": $INBOX_ACTIVE_COUNT,
    "junk_active_count": $JUNK_ACTIVE_COUNT,
    "inbox_initial_size": $INBOX_SIZE,
    "junk_initial_size": $JUNK_SIZE
}
EOF

# Provide contextual file for the user on the Desktop
echo "Before Compaction:" > /home/ga/Desktop/folder_sizes_before_compact.txt
echo "- Inbox: ${INBOX_SIZE} bytes" >> /home/ga/Desktop/folder_sizes_before_compact.txt
echo "- Junk: ${JUNK_SIZE} bytes" >> /home/ga/Desktop/folder_sizes_before_compact.txt
chown ga:ga /home/ga/Desktop/folder_sizes_before_compact.txt

# 7. Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &" 2>/dev/null
sleep 8

# Wait for and maximize window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Thunderbird"; then
        DISPLAY=:1 wmctrl -r "Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Thunderbird" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Dismiss any stray dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== compact_folders task setup complete ==="