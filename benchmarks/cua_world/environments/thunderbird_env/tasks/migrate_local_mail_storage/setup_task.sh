#!/bin/bash
echo "=== Setting up migrate_local_mail_storage task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the simulated secondary drive
ARCHIVE_DRIVE="/home/ga/ArchiveDrive"
mkdir -p "$ARCHIVE_DRIVE"
chown ga:ga "$ARCHIVE_DRIVE"

# Record initial inbox count for state verification
DEFAULT_INBOX="/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"
INITIAL_COUNT=0
if [ -f "$DEFAULT_INBOX" ]; then
    INITIAL_COUNT=$(grep -c "^From " "$DEFAULT_INBOX" 2>/dev/null || echo "0")
fi

# Clean non-numeric characters from count
INITIAL_COUNT=$(echo "$INITIAL_COUNT" | tr -d '[:space:]')
if ! [[ "$INITIAL_COUNT" =~ ^[0-9]+$ ]]; then INITIAL_COUNT=0; fi

echo "$INITIAL_COUNT" > /tmp/initial_inbox_count.txt

# Start Thunderbird if it isn't running
if ! pgrep -f "thunderbird" > /dev/null; then
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    sleep 8
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "thunderbird"; then
        DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="